defmodule TrifleApi.BootstrapController do
  use TrifleApi, :controller

  require Logger

  alias Ecto.{NoResultsError, Query.CastError}
  alias Trifle.Accounts
  alias Trifle.Accounts.User
  alias Trifle.Config
  alias Trifle.Organizations
  alias Trifle.Organizations.{Database, Organization, OrganizationMembership, Project}
  alias Trifle.Repo
  alias TrifleApp.RegistrationConfig

  plug(
    TrifleApi.Plugs.AuthenticateByOrganizationToken
    when action in [
           :me,
           :create_organization,
           :list_sources,
           :create_database,
           :setup_database,
           :create_project,
           :list_tokens,
           :create_token,
           :update_token,
           :delete_token
         ]
  )

  def signup(conn, params) do
    with :ok <- ensure_registration_enabled(),
         {:ok, attrs} <- signup_attrs(params),
         {:ok, %{user: user, organization: organization, membership: membership, token: token}} <-
           create_signup_context(attrs, params, conn) do
      conn
      |> put_status(:created)
      |> json(%{
        data: %{
          user: user_payload(user),
          token: %{value: token},
          organization: organization_payload(organization),
          membership: membership_payload(membership)
        }
      })
    else
      {:error, :registration_disabled} ->
        render_error(conn, :forbidden, "Self-service registration is disabled")

      {:error, :missing_credentials} ->
        render_error(conn, :bad_request, "Missing signup credentials")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset(conn, changeset)

      {:error, :already_member} ->
        render_error(conn, :conflict, "User already belongs to an organization")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, error_message(reason))
    end
  end

  def login(conn, params) do
    with {:ok, email, password} <- login_params(params),
         %User{} = user <- Accounts.get_user_by_email_and_password(email, password),
         {:ok, _record, token} <-
           Organizations.create_organization_api_token(user, organization_token_attrs(conn, params)) do
      membership = Organizations.get_membership_for_user(user)
      organization = membership && membership.organization

      conn
      |> put_status(:created)
      |> json(%{
        data: %{
          user: user_payload(user),
          token: %{value: token},
          organization: organization_payload(organization),
          membership: membership_payload(membership)
        }
      })
    else
      {:error, :missing_credentials} ->
        render_error(conn, :bad_request, "Email and password are required")

      nil ->
        render_error(conn, :unauthorized, "Invalid email or password")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset(conn, changeset)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, error_message(reason))
    end
  end

  def me(%{assigns: %{current_api_user: %User{} = user}} = conn, _params) do
    membership = Organizations.get_membership_for_user(user)
    organization = membership && membership.organization

    json(conn, %{
      data: %{
        user: user_payload(user),
        organization: organization_payload(organization),
        membership: membership_payload(membership)
      }
    })
  end

  def create_organization(%{assigns: %{current_api_user: %User{} = user}} = conn, params) do
    attrs = Map.get(params, "organization") || params

    case Organizations.create_organization_with_owner(attrs, user) do
      {:ok, organization, membership} ->
        bind_result = maybe_bind_current_token_to_organization(conn, organization.id)

        conn
        |> put_status(:created)
        |> json(%{
          data:
            %{
              organization: organization_payload(organization),
              membership: membership_payload(membership)
            }
            |> append_token_operation_status(
              :token_bind_status,
              :token_bind_error,
              bind_result,
              "Failed to bind current token to organization",
              %{organization_id: organization.id}
            )
        })

      {:error, :already_member} ->
        render_error(conn, :conflict, "User already belongs to an organization")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset(conn, changeset)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, error_message(reason))
    end
  end

  def list_sources(%{assigns: %{current_api_user: %User{} = user}} = conn, _params) do
    membership = Organizations.get_membership_for_user(user)

    {projects, databases} =
      case membership do
        %OrganizationMembership{} = membership ->
          {
            membership
            |> Organizations.list_projects_for_membership()
            |> Enum.map(&source_payload(:project, &1)),
            membership.organization_id
            |> Organizations.list_databases_for_org()
            |> Enum.map(&source_payload(:database, &1))
          }

        _ ->
          {[], []}
      end

    json(conn, %{
      data: %{
        projects: projects,
        databases: databases,
        membership: membership_payload(membership)
      }
    })
  end

  def create_database(%{assigns: %{current_api_user: %User{} = user}} = conn, params) do
    with {:ok, %OrganizationMembership{} = membership} <- ensure_membership(user),
         attrs <- normalize_database_attrs(params, membership),
         {:ok, attrs, uploaded_upload} <- maybe_store_sqlite_upload(attrs, params, membership) do
      case Organizations.create_database(attrs) do
        {:ok, %Database{} = database} ->
          grant_result = maybe_grant_source_to_current_token(conn, :database, database.id, true, false)

          conn
          |> put_status(:created)
          |> json(%{
            data:
              %{
                source: source_payload(:database, database)
              }
              |> append_token_operation_status(
                :token_grant_status,
                :token_grant_error,
                grant_result,
                "Failed to grant current token access to database",
                %{source_type: :database, source_id: database.id}
              )
          })

        {:error, %Ecto.Changeset{} = changeset} ->
          cleanup_uploaded_sqlite_upload(uploaded_upload)
          render_changeset(conn, changeset)

        {:error, reason} ->
          cleanup_uploaded_sqlite_upload(uploaded_upload)
          render_error(conn, :unprocessable_entity, error_message(reason))
      end
    else
      {:error, :organization_required} ->
        render_error(conn, :conflict, "User does not belong to an organization")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset(conn, changeset)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, error_message(reason))
    end
  end

  def setup_database(%{assigns: %{current_api_user: %User{} = user}} = conn, %{"id" => id}) do
    with {:ok, %OrganizationMembership{} = membership} <- ensure_membership(user),
         {:ok, %Database{} = database} <- fetch_database(membership, id) do
      case Organizations.setup_database(database) do
        {:ok, message} ->
          checked =
            case Organizations.check_database_status(database) do
              {:ok, updated, _setup_exists} -> updated
              {:error, updated, _error} -> updated
            end

          json(conn, %{
            data: %{
              source: source_payload(:database, checked),
              setup: %{
                status: checked.last_check_status,
                message: message,
                error: checked.last_error
              }
            }
          })

        {:error, message} ->
          render_error(conn, :unprocessable_entity, message)
      end
    else
      {:error, :organization_required} ->
        render_error(conn, :conflict, "User does not belong to an organization")

      {:error, :bad_request} ->
        render_changeset(conn, invalid_source_id_changeset())

      {:error, :not_found} ->
        render_not_found(conn)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, error_message(reason))
    end
  end

  def create_project(%{assigns: %{current_api_user: %User{} = user}} = conn, params) do
    with :ok <- ensure_projects_enabled(),
         {:ok, %OrganizationMembership{} = membership} <- ensure_membership(user),
         attrs <- normalize_project_attrs(params, membership),
         {:ok, %Project{} = project} <-
           Organizations.create_project_for_membership(attrs, membership, user) do
      grant_result = maybe_grant_source_to_current_token(conn, :project, project.id, true, true)

      conn
      |> put_status(:created)
      |> json(%{
        data:
          %{
            source: source_payload(:project, project)
          }
          |> append_token_operation_status(
            :token_grant_status,
            :token_grant_error,
            grant_result,
            "Failed to grant current token access to project",
            %{source_type: :project, source_id: project.id}
          )
      })
    else
      {:error, :projects_disabled} ->
        render_error(conn, :forbidden, "Projects are disabled for this deployment")

      {:error, :organization_required} ->
        render_error(conn, :conflict, "User does not belong to an organization")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset(conn, changeset)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, error_message(reason))
    end
  end

  def list_tokens(%{assigns: %{current_api_user: %User{} = user}} = conn, _params) do
    with {:ok, %OrganizationMembership{} = membership} <- ensure_membership(user),
         :ok <- ensure_token_manager(membership) do
      tokens =
        membership.organization_id
        |> Organizations.list_organization_api_tokens_for_org()
        |> Enum.map(&token_payload/1)

      json(conn, %{data: %{tokens: tokens}})
    else
      {:error, :organization_required} ->
        render_error(conn, :conflict, "User does not belong to an organization")

      {:error, :forbidden} ->
        render_error(conn, :forbidden, "Only organization owners and admins can manage tokens")
    end
  end

  def create_token(%{assigns: %{current_api_user: %User{} = user}} = conn, params) do
    with {:ok, %OrganizationMembership{} = membership} <- ensure_membership(user),
         :ok <- ensure_token_manager(membership),
         {:ok, attrs} <- organization_token_payload(params, membership),
         attrs <- Map.put(attrs, :organization_id, membership.organization_id),
         {:ok, record, value} <- Organizations.create_organization_api_token(user, attrs) do
      conn
      |> put_status(:created)
      |> json(%{data: %{token: token_payload(record, value)}})
    else
      {:error, :organization_required} ->
        render_error(conn, :conflict, "User does not belong to an organization")

      {:error, :forbidden} ->
        render_error(conn, :forbidden, "Only organization owners and admins can manage tokens")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset(conn, changeset)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, error_message(reason))
    end
  end

  def update_token(%{assigns: %{current_api_user: %User{} = user}} = conn, %{"id" => id} = params) do
    with {:ok, %OrganizationMembership{} = membership} <- ensure_membership(user),
         :ok <- ensure_token_manager(membership),
         {:ok, token} <- fetch_org_token(membership, id),
         {:ok, attrs} <- organization_token_payload(params, membership),
         {:ok, updated} <- Organizations.update_organization_api_token(token, attrs) do
      json(conn, %{data: %{token: token_payload(updated)}})
    else
      {:error, :organization_required} ->
        render_error(conn, :conflict, "User does not belong to an organization")

      {:error, :forbidden} ->
        render_error(conn, :forbidden, "Only organization owners and admins can manage tokens")

      {:error, :not_found} ->
        render_not_found(conn)

      {:error, :bad_request} ->
        render_error(conn, :bad_request, "Invalid token id")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset(conn, changeset)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, error_message(reason))
    end
  end

  def delete_token(%{assigns: %{current_api_user: %User{} = user}} = conn, %{"id" => id}) do
    with {:ok, %OrganizationMembership{} = membership} <- ensure_membership(user),
         :ok <- ensure_token_manager(membership),
         {:ok, token} <- fetch_org_token(membership, id),
         {:ok, _deleted} <- Organizations.delete_organization_api_token(token) do
      json(conn, %{data: %{id: id}})
    else
      {:error, :organization_required} ->
        render_error(conn, :conflict, "User does not belong to an organization")

      {:error, :forbidden} ->
        render_error(conn, :forbidden, "Only organization owners and admins can manage tokens")

      {:error, :not_found} ->
        render_not_found(conn)

      {:error, :bad_request} ->
        render_error(conn, :bad_request, "Invalid token id")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, error_message(reason))
    end
  end

  defp ensure_registration_enabled do
    if RegistrationConfig.enabled?(), do: :ok, else: {:error, :registration_disabled}
  end

  defp ensure_projects_enabled do
    if Config.projects_enabled?(), do: :ok, else: {:error, :projects_disabled}
  end

  defp ensure_membership(%User{} = user) do
    case Organizations.get_membership_for_user(user) do
      %OrganizationMembership{} = membership -> {:ok, membership}
      _ -> {:error, :organization_required}
    end
  end

  defp signup_attrs(params) do
    email = params |> Map.get("email") |> normalize_string()
    password = params |> Map.get("password") |> normalize_string()
    name = params |> Map.get("name") |> normalize_string()

    if is_binary(email) and is_binary(password) do
      attrs =
        %{}
        |> Map.put("email", email)
        |> Map.put("password", password)
        |> maybe_put("name", name)

      {:ok, attrs}
    else
      {:error, :missing_credentials}
    end
  end

  defp login_params(params) do
    email = params |> Map.get("email") |> normalize_string()
    password = params |> Map.get("password") |> normalize_string()

    if is_binary(email) and is_binary(password) do
      {:ok, email, password}
    else
      {:error, :missing_credentials}
    end
  end

  defp maybe_create_signup_organization(%User{} = user, params) do
    case params |> Map.get("organization_name") |> normalize_string() do
      nil ->
        {:ok, %{organization: nil, membership: Organizations.get_membership_for_user(user)}}

      name ->
        case Organizations.create_organization_with_owner(%{"name" => name}, user) do
          {:ok, organization, membership} ->
            {:ok, %{organization: organization, membership: membership}}

          {:error, :already_member} ->
            {:error, :already_member}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, changeset}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp create_signup_context(attrs, params, conn) do
    Repo.transaction(fn ->
      with {:ok, %User{} = user} <- Accounts.register_user(attrs),
           {:ok, %{organization: organization, membership: membership}} <-
             maybe_create_signup_organization(user, params),
           {:ok, _record, token} <-
             Organizations.create_organization_api_token(
               user,
               organization_token_attrs(conn, params)
             ) do
        %{
          user: user,
          organization: organization,
          membership: membership,
          token: token
        }
      else
        {:error, reason} -> Repo.rollback(reason)
        reason -> Repo.rollback(reason)
      end
    end)
  end

  defp normalize_database_attrs(params, membership) do
    attrs =
      (Map.get(params, "database") || params)
      |> Map.drop(["organization_id", "id", "inserted_at", "updated_at"])
      |> Map.put("organization_id", membership.organization_id)

    attrs
  end

  defp maybe_store_sqlite_upload(attrs, params, %OrganizationMembership{} = membership) do
    driver = attrs |> Map.get("driver") |> normalize_string()
    sqlite_upload = sqlite_upload_from_params(params)

    cond do
      not is_nil(sqlite_upload) and driver != "sqlite" ->
        {:error, "sqlite_file is only supported for sqlite driver"}

      driver == "sqlite" and not is_nil(sqlite_upload) and
          not match?(%Plug.Upload{}, sqlite_upload) ->
        {:error, "invalid sqlite_file upload"}

      match?(%Plug.Upload{}, sqlite_upload) ->
        case Trifle.SqliteUploads.store_upload_for_database(
               sqlite_upload,
               membership.organization_id
             ) do
          {:ok, %{file_path: uploaded_path, config_patch: config_patch} = uploaded_upload} ->
            updated_attrs =
              attrs
              |> Map.put("file_path", uploaded_path)
              |> Trifle.SqliteUploads.apply_config_patch(config_patch)

            {:ok, updated_attrs, uploaded_upload}

          {:error, reason} ->
            {:error, reason}
        end

      true ->
        {:ok, attrs, nil}
    end
  end

  defp sqlite_upload_from_params(params) do
    payload = Map.get(params, "database") || %{}
    Map.get(params, "sqlite_file") || Map.get(payload, "sqlite_file")
  end

  defp cleanup_uploaded_sqlite_upload(nil), do: :ok

  defp cleanup_uploaded_sqlite_upload(%{file_path: path, config_patch: config_patch}) do
    config = if is_map(config_patch), do: config_patch, else: %{}

    case Trifle.SqliteUploads.delete_managed_upload(path, config) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to delete managed sqlite upload during bootstrap cleanup",
          sqlite_upload_path: path,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp cleanup_uploaded_sqlite_upload(_), do: :ok

  defp normalize_project_attrs(params, membership) do
    payload = Map.get(params, "project") || params
    granularities = parse_granularities(payload["granularities"])

    payload
    |> Map.drop(["organization_id", "id", "inserted_at", "updated_at"])
    |> Map.put_new("time_zone", "UTC")
    |> Map.put_new("beginning_of_week", 1)
    |> Map.put_new("expire_after", Project.basic_retention_seconds())
    |> Map.put("organization_id", membership.organization_id)
    |> maybe_put("granularities", granularities)
    |> maybe_put(
      "default_granularity",
      default_granularity(payload["default_granularity"], granularities)
    )
  end

  defp fetch_database(%OrganizationMembership{} = membership, id) do
    {:ok, Organizations.get_database_for_org!(membership.organization_id, id)}
  rescue
    NoResultsError -> {:error, :not_found}
    CastError -> {:error, :bad_request}
  end

  defp maybe_grant_source_to_current_token(
         %{assigns: %{current_api_token: token}},
         source_type,
         source_id,
         read,
         write
       )
       when is_map(token) do
    case Organizations.grant_organization_api_token_source_access(
           token,
           source_type,
           source_id,
           read,
           write
         ) do
      {:ok, _updated} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_grant_source_to_current_token(_conn, _source_type, _source_id, _read, _write), do: :ok

  defp maybe_bind_current_token_to_organization(
         %{assigns: %{current_api_token: token}},
         organization_id
       )
       when is_map(token) and is_binary(organization_id) do
    case token.organization_id do
      ^organization_id ->
        :ok

      nil ->
        case Organizations.update_organization_api_token(token, %{organization_id: organization_id}) do
          {:ok, _updated} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _other ->
        :ok
    end
  end

  defp maybe_bind_current_token_to_organization(_conn, _organization_id), do: :ok

  defp append_token_operation_status(
         data,
         status_field,
         error_field,
         result,
         log_message,
         metadata
       )
       when is_map(data) do
    case result do
      :ok ->
        Map.put(data, status_field, "ok")

      {:error, reason} ->
        log_metadata =
          metadata
          |> Map.put(:reason, inspect(reason))
          |> Enum.into([])

        Logger.warning(log_message, log_metadata)

        data
        |> Map.put(status_field, "error")
        |> Map.put(error_field, error_message(reason))
    end
  end

  defp ensure_token_manager(%OrganizationMembership{} = membership) do
    if Organizations.membership_owner?(membership) or Organizations.membership_admin?(membership) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp fetch_org_token(%OrganizationMembership{} = membership, token_id) do
    {:ok, Organizations.get_organization_api_token_for_org!(membership.organization_id, token_id)}
  rescue
    NoResultsError -> {:error, :not_found}
    CastError -> {:error, :bad_request}
  end

  defp organization_token_payload(params, %OrganizationMembership{} = membership) do
    payload = Map.get(params, "token") || params
    name = payload |> Map.get("name") |> normalize_string()
    permissions = build_permissions_payload(payload, membership)

    with {:ok, expires_at} <- payload |> Map.get("expires_at") |> normalize_expires_at() do
      {:ok,
       %{}
       |> maybe_put(:name, name)
       |> maybe_put(:permissions, permissions)
       |> maybe_put(:expires_at, expires_at)}
    end
  end

  defp build_permissions_payload(payload, %OrganizationMembership{} = membership) do
    permissions =
      payload
      |> Map.get("permissions")
      |> Organizations.normalize_token_permissions()
      |> maybe_apply_wildcard(payload)
      |> maybe_apply_legacy_source_grant(payload, membership)
      |> maybe_apply_grants(payload, membership)

    permissions
  end

  defp maybe_apply_wildcard(permissions, payload) do
    wildcard_read = Map.get(payload, "wildcard_read")
    wildcard_write = Map.get(payload, "wildcard_write")

    if is_nil(wildcard_read) and is_nil(wildcard_write) do
      permissions
    else
      put_in(permissions, ["wildcard"], %{
        "read" => parse_bool(wildcard_read),
        "write" => parse_bool(wildcard_write)
      })
    end
  end

  defp maybe_apply_legacy_source_grant(permissions, payload, membership) do
    source_type = payload |> Map.get("source_type") |> normalize_string()
    source_id = payload |> Map.get("source_id") |> normalize_string()
    read = parse_bool(Map.get(payload, "read"))
    write = parse_bool(Map.get(payload, "write"))

    if is_binary(source_id) do
      grants = [%{"source_type" => source_type, "source_id" => source_id, "read" => read, "write" => write}]
      apply_grants(permissions, grants, membership)
    else
      permissions
    end
  end

  defp maybe_apply_grants(permissions, payload, membership) do
    case Map.get(payload, "grants") do
      list when is_list(list) -> apply_grants(permissions, list, membership)
      _ -> permissions
    end
  end

  defp apply_grants(permissions, grants, %OrganizationMembership{} = membership) do
    Enum.reduce(grants, permissions, fn grant, acc ->
      case normalize_grant(grant, membership) do
        {:ok, source_type, source_id, read, write} ->
          with {:ok, key} <- Organizations.source_key(source_type, source_id) do
            put_in(acc, ["sources", key], %{"read" => read, "write" => write})
          else
            _ -> acc
          end

        _ ->
          acc
      end
    end)
  end

  defp normalize_grant(grant, %OrganizationMembership{} = membership) when is_map(grant) do
    source_id = grant |> Map.get("source_id") |> normalize_string()
    source_type = grant |> Map.get("source_type") |> normalize_string()
    read = parse_bool(Map.get(grant, "read"))
    write = parse_bool(Map.get(grant, "write"))

    cond do
      is_nil(source_id) ->
        :error

      is_binary(source_type) ->
        {:ok, source_type, source_id, read, write}

      true ->
        case Organizations.get_source_for_org(membership.organization_id, source_id) do
          {:ok, resolved_type, _record} -> {:ok, resolved_type, source_id, read, write}
          _ -> :error
        end
    end
  end

  defp normalize_grant(_grant, _membership), do: :error

  defp token_payload(token, value \\ nil) do
    payload = %{
      id: token.id,
      name: token.name,
      token_last5: token.token_last5,
      organization_id: token.organization_id,
      user_id: token.user_id,
      permissions: Organizations.normalize_token_permissions(token.permissions),
      created_by: token.created_by,
      created_from: token.created_from,
      last_used_at: token.last_used_at,
      last_used_from: token.last_used_from,
      expires_at: token.expires_at,
      inserted_at: token.inserted_at,
      updated_at: token.updated_at
    }

    if is_binary(value) do
      Map.put(payload, :value, value)
    else
      payload
    end
  end

  defp source_payload(:database, %Database{} = database) do
    %{
      id: database.id,
      type: "database",
      display_name: database.display_name,
      default_timeframe: database.default_timeframe,
      default_granularity: database.default_granularity,
      available_granularities: available_database_granularities(database),
      time_zone: database.time_zone || "UTC",
      setup_status: database.last_check_status
    }
  end

  defp source_payload(:project, %Project{} = project) do
    %{
      id: project.id,
      type: "project",
      display_name: project.name,
      default_timeframe: project.default_timeframe,
      default_granularity: project.default_granularity,
      available_granularities: available_project_granularities(project),
      time_zone: project.time_zone || "UTC"
    }
  end

  defp available_database_granularities(%Database{granularities: list})
       when is_list(list) and list != [],
       do: list

  defp available_database_granularities(_), do: Database.default_granularities()

  defp available_project_granularities(%Project{granularities: list})
       when is_list(list) and list != [],
       do: list

  defp available_project_granularities(_), do: Project.default_granularities()

  defp user_payload(%User{} = user) do
    %{
      id: user.id,
      email: user.email,
      name: user.name
    }
  end

  defp organization_payload(nil), do: nil

  defp organization_payload(%Organization{} = organization) do
    %{
      id: organization.id,
      name: organization.name,
      slug: organization.slug
    }
  end

  defp membership_payload(nil), do: nil

  defp membership_payload(%OrganizationMembership{} = membership) do
    %{
      id: membership.id,
      role: membership.role,
      organization_id: membership.organization_id
    }
  end

  defp token_name(params) do
    params
    |> Map.get("token_name")
    |> normalize_string()
    |> case do
      nil -> "CLI token"
      value -> value
    end
  end

  defp organization_token_attrs(conn, params) do
    %{
      name: token_name(params),
      created_by: token_created_by(conn, params),
      created_from: token_created_from(conn, params)
    }
  end

  defp token_created_by(conn, params) do
    params
    |> Map.get("client_name")
    |> normalize_string()
    |> case do
      nil ->
        conn
        |> get_req_header("user-agent")
        |> List.first()
        |> normalize_string()

      name ->
        name
    end
  end

  defp token_created_from(conn, params) do
    params
    |> Map.get("client_host")
    |> normalize_string()
    |> case do
      nil ->
        conn
        |> get_req_header("x-trifle-client-host")
        |> List.first()
        |> normalize_string()

      host ->
        host
    end
  end

  defp parse_granularities(nil), do: nil

  defp parse_granularities(value) when is_binary(value) do
    parsed =
      value
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if parsed == [], do: nil, else: parsed
  end

  defp parse_granularities(value) when is_list(value) do
    parsed =
      value
      |> Enum.map(fn
        val when is_binary(val) -> String.trim(val)
        val -> to_string(val)
      end)
      |> Enum.reject(&(&1 == ""))

    if parsed == [], do: nil, else: parsed
  end

  defp parse_granularities(_), do: nil

  defp default_granularity(value, _granularities) when is_binary(value) and value != "", do: value
  defp default_granularity(_value, [first | _]), do: first
  defp default_granularity(_value, _), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(_), do: nil

  defp parse_bool(value) when is_boolean(value), do: value

  defp parse_bool(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "true" -> true
      "1" -> true
      "yes" -> true
      _ -> false
    end
  end

  defp parse_bool(_), do: false

  defp normalize_expires_at(nil), do: {:ok, nil}

  defp normalize_expires_at(value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        {:ok, nil}

      trimmed ->
        case DateTime.from_iso8601(trimmed) do
          {:ok, datetime, _} -> {:ok, datetime}
          _ -> {:error, :invalid_expires_at}
        end
    end
  end

  defp normalize_expires_at(%DateTime{} = value), do: {:ok, value}
  defp normalize_expires_at(_), do: {:error, :invalid_expires_at}

  defp invalid_source_id_changeset do
    {%{}, %{source_id: :string}}
    |> Ecto.Changeset.cast(%{source_id: "invalid"}, [:source_id])
    |> Ecto.Changeset.add_error(:source_id, "is invalid")
  end

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)

  defp render_changeset(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(TrifleApp.ChangesetJSON)
    |> render("error.json", changeset: changeset)
  end

  defp render_not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(TrifleApi.ErrorJSON)
    |> render("404.json")
  end

  defp render_error(conn, status, detail) do
    conn
    |> put_status(status)
    |> json(%{errors: %{detail: detail}})
  end

  defp error_message(:invalid_expires_at),
    do: "expires_at must be a valid ISO8601 datetime (or omitted)"

  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason), do: inspect(reason)
end
