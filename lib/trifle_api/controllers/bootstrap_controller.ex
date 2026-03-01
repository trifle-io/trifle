defmodule TrifleApi.BootstrapController do
  use TrifleApi, :controller

  alias Ecto.NoResultsError
  alias Trifle.Accounts
  alias Trifle.Accounts.User
  alias Trifle.Config
  alias Trifle.Organizations
  alias Trifle.Organizations.{Database, Organization, OrganizationMembership, Project}
  alias TrifleApp.RegistrationConfig

  plug(
    TrifleApi.Plugs.AuthenticateByUserToken
    when action in [
           :me,
           :create_organization,
           :list_sources,
           :create_database,
           :setup_database,
           :create_project,
           :create_source_token
         ]
  )

  def signup(conn, params) do
    with :ok <- ensure_registration_enabled(),
         {:ok, attrs} <- signup_attrs(params),
         {:ok, %User{} = user} <- Accounts.register_user(attrs),
         {:ok, %{organization: organization, membership: membership}} <-
           maybe_create_signup_organization(user, params),
         {:ok, _record, token} <-
           Accounts.create_user_api_token(user, user_token_attrs(conn, params)) do
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
           Accounts.create_user_api_token(user, user_token_attrs(conn, params)) do
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
        conn
        |> put_status(:created)
        |> json(%{
          data: %{
            organization: organization_payload(organization),
            membership: membership_payload(membership)
          }
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
         {:ok, %Database{} = database} <- Organizations.create_database(attrs) do
      conn
      |> put_status(:created)
      |> json(%{
        data: %{
          source: source_payload(:database, database)
        }
      })
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
      conn
      |> put_status(:created)
      |> json(%{
        data: %{
          source: source_payload(:project, project)
        }
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

  def create_source_token(%{assigns: %{current_api_user: %User{} = user}} = conn, params) do
    with {:ok, %OrganizationMembership{} = membership} <- ensure_membership(user),
         {:ok, payload} <- source_token_payload(params),
         {:ok, result} <- issue_source_token(membership, payload) do
      conn
      |> put_status(:created)
      |> json(%{data: result})
    else
      {:error, :organization_required} ->
        render_error(conn, :conflict, "User does not belong to an organization")

      {:error, :not_found} ->
        render_not_found(conn)

      {:error, :invalid_source_type} ->
        render_error(conn, :bad_request, "source_type must be database or project")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset(conn, changeset)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, error_message(reason))
    end
  end

  def create_source_token(conn, _params) do
    render_error(conn, :bad_request, "source_type and source_id are required")
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

  defp normalize_database_attrs(params, membership) do
    attrs =
      (Map.get(params, "database") || params)
      |> Map.drop(["organization_id", "id", "inserted_at", "updated_at"])
      |> Map.put("organization_id", membership.organization_id)

    attrs
  end

  defp normalize_project_attrs(params, membership) do
    payload = Map.get(params, "project") || params
    granularities = parse_granularities(payload["granularities"])

    payload
    |> Map.drop(["organization_id", "id", "inserted_at", "updated_at"])
    |> Map.put_new("time_zone", "UTC")
    |> Map.put_new("beginning_of_week", 42)
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
  end

  defp fetch_project(%OrganizationMembership{} = membership, id) do
    {:ok, Organizations.get_project_for_org!(membership.organization_id, id)}
  rescue
    NoResultsError -> {:error, :not_found}
  end

  defp source_token_payload(params) do
    payload = Map.get(params, "source_token") || params
    source_type = payload |> Map.get("source_type") |> normalize_string()
    source_id = payload |> Map.get("source_id") |> normalize_string()
    name = payload |> Map.get("name") |> normalize_string()
    read = normalize_boolean(payload["read"], true)
    write = normalize_boolean(payload["write"], true)

    if is_binary(source_type) and is_binary(source_id) do
      {:ok,
       %{
         source_type: source_type,
         source_id: source_id,
         name: name || "CLI source token",
         read: read,
         write: write
       }}
    else
      {:error, :invalid_source_type}
    end
  end

  defp issue_source_token(membership, %{source_type: "database", source_id: source_id, name: name}) do
    with {:ok, %Database{} = database} <- fetch_database(membership, source_id),
         {:ok, token_record} <-
           Organizations.create_databases_database_token(%{"name" => name}, database) do
      {:ok,
       %{
         token: %{value: token_record.token, read: true, write: false},
         source: source_payload(:database, database)
       }}
    end
  end

  defp issue_source_token(membership, %{
         source_type: "project",
         source_id: source_id,
         name: name,
         read: read,
         write: write
       }) do
    with {:ok, %Project{} = project} <- fetch_project(membership, source_id),
         {:ok, token_record} <-
           Organizations.create_projects_project_token(
             %{"name" => name, "read" => read, "write" => write},
             project
           ) do
      {:ok,
       %{
         token: %{value: token_record.token, read: token_record.read, write: token_record.write},
         source: source_payload(:project, project)
       }}
    end
  end

  defp issue_source_token(_membership, %{source_type: _type}), do: {:error, :invalid_source_type}

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

  defp user_token_attrs(conn, params) do
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

  defp normalize_boolean(nil, default), do: default
  defp normalize_boolean(value, _default) when is_boolean(value), do: value

  defp normalize_boolean(value, default) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "true" -> true
      "false" -> false
      _ -> default
    end
  end

  defp normalize_boolean(_value, default), do: default

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

  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason), do: inspect(reason)
end
