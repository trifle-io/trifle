defmodule Trifle.Organizations.Tokens do
  @moduledoc """
  API tokens across all scopes: organization API tokens (auth, permission
  checks, source grants, caching, last-used tracking), project tokens, and
  database tokens.
  """

  import Ecto.Query, warn: false

  alias Trifle.Accounts.User
  alias Trifle.Organizations
  alias Trifle.Organizations.Database
  alias Trifle.Organizations.DatabaseToken
  alias Trifle.Organizations.Organization
  alias Trifle.Organizations.OrganizationApiToken
  alias Trifle.Organizations.OrganizationMembership
  alias Trifle.Organizations.Project
  alias Trifle.Organizations.ProjectToken
  alias Trifle.Organizations.TokenCache
  alias Trifle.Organizations.TokenTouchThrottle
  alias Trifle.Repo

  @organization_api_token_cache_ttl_ms 60_000

  def list_organization_api_tokens_for_org(%Organization{} = organization) do
    list_organization_api_tokens_for_org(organization.id)
  end

  def list_organization_api_tokens_for_org(organization_id) when is_binary(organization_id) do
    from(t in OrganizationApiToken,
      where: t.organization_id == ^organization_id,
      order_by: [desc: t.inserted_at]
    )
    |> Repo.all()
  end

  def get_organization_api_token_for_org!(organization_id, token_id)
      when is_binary(organization_id) and is_binary(token_id) do
    Repo.get_by!(OrganizationApiToken, id: token_id, organization_id: organization_id)
  end

  def get_organization_api_token_for_org(organization_id, token_id)
      when is_binary(organization_id) and is_binary(token_id) do
    Repo.get_by(OrganizationApiToken, id: token_id, organization_id: organization_id)
  end

  def create_organization_api_token(%User{} = user, attrs \\ %{}) do
    token_value = OrganizationApiToken.build_token()
    attrs = prepare_organization_api_token_attrs(user, attrs, token_value)

    case %OrganizationApiToken{}
         |> OrganizationApiToken.changeset(attrs)
         |> Repo.insert() do
      {:ok, record} -> {:ok, record, token_value}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def update_organization_api_token(%OrganizationApiToken{} = token, attrs) do
    attrs = normalize_organization_api_token_update_attrs(attrs)

    token
    |> OrganizationApiToken.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        TokenCache.invalidate(updated.token_hash)
        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def bind_organization_api_token_to_organization(
        %OrganizationApiToken{} = token,
        organization_id
      )
      when is_binary(organization_id) do
    token
    |> OrganizationApiToken.changeset(%{organization_id: organization_id})
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        TokenCache.invalidate(updated.token_hash)
        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def bind_organization_api_token_to_organization(_token, _organization_id),
    do: {:error, :invalid_organization_id}

  def delete_organization_api_token(%OrganizationApiToken{} = token) do
    case Repo.delete(token) do
      {:ok, deleted} ->
        TokenCache.invalidate(deleted.token_hash)
        {:ok, deleted}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def change_organization_api_token(%OrganizationApiToken{} = token, attrs \\ %{}) do
    attrs = normalize_organization_api_token_update_attrs(attrs)
    OrganizationApiToken.changeset(token, attrs)
  end

  def get_api_token_auth(token) when is_binary(token) do
    token_hash = OrganizationApiToken.hash_token(token)

    case TokenCache.get(token_hash) do
      {:ok, payload} ->
        {:ok, payload}

      :error ->
        token
        |> OrganizationApiToken.valid_query()
        |> Repo.one()
        |> Repo.preload([:user, :organization])
        |> case do
          %OrganizationApiToken{user: %User{} = user} = record ->
            payload = %{token: record, user: user, organization: record.organization}
            cache_ttl_ms = token_cache_ttl_ms(record)

            if cache_ttl_ms > 0 do
              TokenCache.put(token_hash, payload, cache_ttl_ms)
            end

            {:ok, payload}

          _ ->
            {:error, :not_found}
        end
    end
  end

  def get_api_token_auth(_), do: {:error, :not_found}

  def touch_organization_api_token(token, attrs \\ %{})

  def touch_organization_api_token(token, attrs) when is_binary(token) do
    token_hash = OrganizationApiToken.hash_token(token)

    if TokenTouchThrottle.allow?(token_hash) do
      attrs = attrs || %{}
      attrs = Map.new(attrs)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      updates =
        [last_used_at: now]
        |> maybe_put_token_metadata_update(
          :last_used_from,
          token_metadata_value(attrs, :last_used_from)
        )

      token
      |> OrganizationApiToken.valid_query()
      |> Repo.update_all(set: updates)
    end

    :ok
  end

  def touch_organization_api_token(_token, _attrs), do: :ok

  def grant_organization_api_token_source_access(
        %OrganizationApiToken{} = token,
        source_type,
        source_id,
        read,
        write
      ) do
    with {:ok, source_key} <- source_key(source_type, source_id) do
      case Repo.transaction(fn ->
             locked_token =
               from(t in OrganizationApiToken,
                 where: t.id == ^token.id,
                 lock: "FOR UPDATE"
               )
               |> Repo.one()

             case locked_token do
               %OrganizationApiToken{} = locked_token ->
                 permissions =
                   locked_token.permissions
                   |> normalize_token_permissions()
                   |> put_in(
                     ["sources", source_key],
                     %{"read" => permission_boolean(read), "write" => permission_boolean(write)}
                   )

                 case update_organization_api_token(locked_token, %{permissions: permissions}) do
                   {:ok, updated_token} -> updated_token
                   {:error, reason} -> Repo.rollback(reason)
                 end

               _ ->
                 Repo.rollback(:not_found)
             end
           end) do
        {:ok, updated_token} -> {:ok, updated_token}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def ensure_token_permission(
        %OrganizationApiToken{} = token,
        source_type,
        source_id,
        mode
      ) do
    if token_has_permission?(token.permissions, source_type, source_id, mode) do
      :ok
    else
      {:error, :invalid_permissions}
    end
  end

  def token_has_permission?(permissions, source_type, source_id, mode) do
    permissions = normalize_token_permissions(permissions)
    wildcard = Map.get(permissions, "wildcard", %{})

    source_grant =
      with {:ok, key} <- source_key(source_type, source_id) do
        Map.get(Map.get(permissions, "sources", %{}), key, %{})
      else
        _ -> %{}
      end

    wildcard_read = permission_boolean(Map.get(wildcard, "read"))
    wildcard_write = permission_boolean(Map.get(wildcard, "write"))
    source_read = permission_boolean(Map.get(source_grant, "read"))
    source_write = permission_boolean(Map.get(source_grant, "write"))
    read_allowed = wildcard_read || source_read
    write_allowed = wildcard_write || source_write

    case mode do
      :read -> read_allowed
      :write -> write_allowed
      :any -> read_allowed || write_allowed
      :none -> true
      nil -> false
      _ -> false
    end
  end

  def source_permission(%OrganizationApiToken{} = token, source_type, source_id) do
    permissions = normalize_token_permissions(token.permissions)
    wildcard = Map.get(permissions, "wildcard", %{})

    source_grant =
      with {:ok, key} <- source_key(source_type, source_id) do
        Map.get(Map.get(permissions, "sources", %{}), key, %{})
      else
        _ -> %{}
      end

    %{
      read:
        permission_boolean(Map.get(wildcard, "read")) ||
          permission_boolean(Map.get(source_grant, "read")),
      write:
        permission_boolean(Map.get(wildcard, "write")) ||
          permission_boolean(Map.get(source_grant, "write"))
    }
  end

  def source_permission(_token, _source_type, _source_id), do: %{read: false, write: false}

  def source_key(source_type, source_id) do
    with {:ok, source_type} <- normalize_token_source_type(source_type),
         {:ok, source_id} <- Ecto.UUID.cast(source_id) do
      {:ok, "#{source_type}:#{source_id}"}
    else
      _ -> {:error, :invalid_source}
    end
  end

  def normalize_token_permissions(permissions) do
    wildcard =
      permissions
      |> token_permissions_value("wildcard")
      |> normalize_permission_grant()

    sources =
      permissions
      |> token_permissions_value("sources")
      |> normalize_token_sources()

    %{"wildcard" => wildcard, "sources" => sources}
  end

  defp prepare_organization_api_token_attrs(%User{} = user, attrs, token_value) do
    attrs = attrs || %{}
    attrs = Map.new(attrs)

    organization_id =
      token_metadata_value(attrs, :organization_id) || organization_id_for_user(user)

    attrs
    |> Map.put(:user_id, user.id)
    |> Map.put(:token_hash, OrganizationApiToken.hash_token(token_value))
    |> Map.put(:token_last5, OrganizationApiToken.token_last5(token_value))
    |> Map.put(
      :permissions,
      normalize_token_permissions(token_metadata_value(attrs, :permissions))
    )
    |> Map.put_new(:name, "CLI token")
    |> maybe_put_token_metadata(:organization_id, organization_id)
    |> maybe_put_token_metadata(:created_by, token_metadata_value(attrs, :created_by))
    |> maybe_put_token_metadata(:created_from, token_metadata_value(attrs, :created_from))
    |> maybe_put_token_metadata(:expires_at, token_metadata_value(attrs, :expires_at))
  end

  defp normalize_organization_api_token_update_attrs(attrs) do
    attrs = attrs || %{}

    protected_keys = [
      :id,
      "id",
      :organization_id,
      "organization_id",
      :user_id,
      "user_id",
      :token_hash,
      "token_hash",
      :token_last5,
      "token_last5",
      :token,
      "token",
      :created_by,
      "created_by",
      :created_from,
      "created_from",
      :last_used_at,
      "last_used_at",
      :last_used_from,
      "last_used_from",
      :inserted_at,
      "inserted_at",
      :updated_at,
      "updated_at",
      :revoked_at,
      "revoked_at"
    ]

    attrs =
      attrs
      |> Map.new()
      |> Map.drop(protected_keys)

    permissions = token_metadata_value(attrs, :permissions)

    if is_nil(permissions) do
      attrs
    else
      Map.put(attrs, :permissions, normalize_token_permissions(permissions))
    end
  end

  defp organization_id_for_user(%User{} = user) do
    case Organizations.get_membership_for_user(user) do
      %OrganizationMembership{} = membership -> membership.organization_id
      _ -> nil
    end
  end

  defp token_permissions_value(%{} = map, key) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp token_permissions_value(_, _), do: nil

  defp normalize_token_sources(%{} = sources) do
    Enum.reduce(sources, %{}, fn {key, value}, acc ->
      case normalize_token_source_key(key) do
        {:ok, normalized_key} ->
          Map.put(acc, normalized_key, normalize_permission_grant(value))

        {:error, :invalid_source} ->
          acc

        :error ->
          acc
      end
    end)
  end

  defp normalize_token_sources(_), do: %{}

  defp normalize_token_source_key(key) do
    key = to_string(key)

    case String.split(key, ":", parts: 2) do
      [source_type, source_id] ->
        source_key(source_type, source_id)

      _ ->
        :error
    end
  end

  defp normalize_permission_grant(%{} = grant) do
    %{
      "read" => permission_boolean(token_permissions_value(grant, "read")),
      "write" => permission_boolean(token_permissions_value(grant, "write"))
    }
  end

  defp normalize_permission_grant(_), do: %{"read" => false, "write" => false}

  defp normalize_token_source_type(source_type) when is_binary(source_type) do
    case String.trim(source_type) do
      "project" -> {:ok, "project"}
      "database" -> {:ok, "database"}
      _ -> {:error, :invalid_source}
    end
  end

  defp normalize_token_source_type(:project), do: {:ok, "project"}
  defp normalize_token_source_type(:database), do: {:ok, "database"}
  defp normalize_token_source_type(_), do: {:error, :invalid_source}

  defp permission_boolean(value) when is_boolean(value), do: value
  defp permission_boolean("true"), do: true
  defp permission_boolean("false"), do: false
  defp permission_boolean(_), do: false

  defp token_cache_ttl_ms(%OrganizationApiToken{expires_at: nil}),
    do: @organization_api_token_cache_ttl_ms

  defp token_cache_ttl_ms(%OrganizationApiToken{expires_at: %DateTime{} = expires_at}) do
    expires_in_ms = DateTime.diff(expires_at, DateTime.utc_now(), :millisecond)

    expires_in_ms
    |> max(0)
    |> min(@organization_api_token_cache_ttl_ms)
  end

  defp token_cache_ttl_ms(_), do: @organization_api_token_cache_ttl_ms

  defp token_metadata_value(attrs, key) when is_map(attrs) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp token_metadata_value(_attrs, _key), do: nil

  defp maybe_put_token_metadata(attrs, _key, nil), do: attrs
  defp maybe_put_token_metadata(attrs, key, value), do: Map.put(attrs, key, value)

  defp maybe_put_token_metadata_update(updates, _key, nil), do: updates
  defp maybe_put_token_metadata_update(updates, key, value), do: Keyword.put(updates, key, value)

  @doc """
  Returns the list of project_tokens.

  ## Examples

      iex> list_project_tokens()
      [%ProjectToken{}, ...]

  """
  def list_project_tokens do
    Repo.all(ProjectToken)
  end

  def list_projects_project_tokens(%Project{} = project) do
    query =
      from(
        pt in ProjectToken,
        where: pt.project_id == ^project.id
      )

    Repo.all(query)
  end

  @doc """
  Gets a single project_token.

  Raises `Ecto.NoResultsError` if the Project token does not exist.

  ## Examples

      iex> get_project_token!(123)
      %ProjectToken{}

      iex> get_project_token!(456)
      ** (Ecto.NoResultsError)

  """
  def get_project_token!(id), do: Repo.get!(ProjectToken, id)

  def get_project_by_token(token) when is_binary(token) do
    with %ProjectToken{} = record <- Repo.get_by(ProjectToken, token: token),
         record <- Repo.preload(record, :project),
         {:ok, _id} <-
           Phoenix.Token.verify(TrifleWeb.Endpoint, "project auth", record.token,
             max_age: 86400 * 365
           ),
         %Project{} = project <- record.project do
      {:ok, project, record}
    else
      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Creates a project_token.

  ## Examples

      iex> create_project_token(%{field: value})
      {:ok, %ProjectToken{}}

      iex> create_project_token(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_project_token(attrs \\ %{}) do
    %ProjectToken{}
    |> ProjectToken.changeset(attrs)
    |> Repo.insert()
  end

  def create_projects_project_token(attrs \\ %{}, %Project{} = project) do
    attrs = Map.put(attrs, "project", project)

    %ProjectToken{}
    |> ProjectToken.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a project_token.

  ## Examples

      iex> update_project_token(project_token, %{field: new_value})
      {:ok, %ProjectToken{}}

      iex> update_project_token(project_token, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_project_token(%ProjectToken{} = project_token, attrs) do
    project_token
    |> ProjectToken.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a project_token.

  ## Examples

      iex> delete_project_token(project_token)
      {:ok, %ProjectToken{}}

      iex> delete_project_token(project_token)
      {:error, %Ecto.Changeset{}}

  """
  def delete_project_token(%ProjectToken{} = project_token) do
    Repo.delete(project_token)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking project_token changes.

  ## Examples

      iex> change_project_token(project_token)
      %Ecto.Changeset{data: %ProjectToken{}}

  """
  def change_project_token(%ProjectToken{} = project_token, attrs \\ %{}) do
    ProjectToken.changeset(project_token, attrs)
  end

  @doc """
  Returns the list of database_tokens.

  ## Examples

      iex> list_database_tokens()
      [%DatabaseToken{}, ...]

  """
  def list_database_tokens do
    Repo.all(DatabaseToken)
  end

  def list_databases_database_tokens(%Database{} = database) do
    query =
      from(
        dt in DatabaseToken,
        where: dt.database_id == ^database.id
      )

    Repo.all(query)
  end

  @doc """
  Gets a single database_token.

  Raises `Ecto.NoResultsError` if the Database token does not exist.

  ## Examples

      iex> get_database_token!(123)
      %DatabaseToken{}

      iex> get_database_token!(456)
      ** (Ecto.NoResultsError)

  """
  def get_database_token!(id), do: Repo.get!(DatabaseToken, id)

  def get_database_by_token(token) when is_binary(token) do
    with %DatabaseToken{} = record <- Repo.get_by(DatabaseToken, token: token),
         record <- Repo.preload(record, :database),
         {:ok, _id} <-
           Phoenix.Token.verify(TrifleWeb.Endpoint, "database auth", record.token,
             max_age: 86400 * 365
           ),
         %Database{} = database <- record.database do
      {:ok, database, record}
    else
      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Creates a database_token.

  ## Examples

      iex> create_database_token(%{field: value})
      {:ok, %DatabaseToken{}}

      iex> create_database_token(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_database_token(attrs \\ %{}) do
    %DatabaseToken{}
    |> DatabaseToken.changeset(attrs)
    |> Repo.insert()
  end

  def create_databases_database_token(attrs \\ %{}, %Database{} = database) do
    attrs = Map.put(attrs, "database", database)

    %DatabaseToken{}
    |> DatabaseToken.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a database_token.

  ## Examples

      iex> update_database_token(database_token, %{field: new_value})
      {:ok, %DatabaseToken{}}

      iex> update_database_token(database_token, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_database_token(%DatabaseToken{} = database_token, attrs) do
    database_token
    |> DatabaseToken.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a database_token.

  ## Examples

      iex> delete_database_token(database_token)
      {:ok, %DatabaseToken{}}

      iex> delete_database_token(database_token)
      {:error, %Ecto.Changeset{}}

  """
  def delete_database_token(%DatabaseToken{} = database_token) do
    Repo.delete(database_token)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking database_token changes.

  ## Examples

      iex> change_database_token(database_token)
      %Ecto.Changeset{data: %DatabaseToken{}}

  """
  def change_database_token(%DatabaseToken{} = database_token, attrs \\ %{}) do
    DatabaseToken.changeset(database_token, attrs)
  end
end
