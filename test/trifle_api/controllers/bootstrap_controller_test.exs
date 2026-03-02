defmodule TrifleApi.BootstrapControllerTest do
  use TrifleApp.ConnCase

  import Trifle.AccountsFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Accounts
  alias Trifle.Organizations

  setup %{conn: conn} do
    user = user_fixture()
    {:ok, _token_record, user_token} = Accounts.create_user_api_token(user, %{name: "Bootstrap"})

    {:ok, conn: api_conn(conn), user: user, user_token: user_token}
  end

  describe "POST /api/v1/bootstrap/signup" do
    test "creates user token and optional organization", %{conn: conn} do
      email = unique_user_email()

      conn =
        conn
        |> put_req_header("user-agent", "trifle-cli-test")
        |> put_req_header("x-trifle-client-host", "agent-host")
        |> post(~p"/api/v1/bootstrap/signup", %{
          "email" => email,
          "password" => valid_user_password(),
          "organization_name" => "Bootstrap Org"
        })

      assert %{
               "data" => %{
                 "user" => %{"id" => _id},
                 "token" => %{"value" => token},
                 "organization" => %{"name" => "Bootstrap Org"},
                 "membership" => %{"role" => "owner"}
               }
             } = json_response(conn, 201)

      assert is_binary(token)
      assert String.starts_with?(token, "trf_uat_")

      created_user = Accounts.get_user_by_email(email)
      assert [record] = Accounts.list_user_api_tokens(created_user)
      assert record.created_by == "trifle-cli-test"
      assert record.created_from == "agent-host"
    end
  end

  describe "POST /api/v1/bootstrap/login" do
    test "issues new user token for valid credentials", %{conn: conn, user: user} do
      user_id = user.id

      conn =
        post(conn, ~p"/api/v1/bootstrap/login", %{
          "email" => user.email,
          "password" => valid_user_password()
        })

      assert %{
               "data" => %{
                 "user" => %{"id" => ^user_id},
                 "token" => %{"value" => token}
               }
             } = json_response(conn, 201)

      assert is_binary(token)
    end
  end

  describe "authenticated bootstrap endpoints" do
    test "GET /api/v1/bootstrap/me returns user and membership context", %{
      conn: conn,
      user: user,
      user_token: user_token
    } do
      user_id = user.id

      {:ok, organization, _membership} =
        Organizations.create_organization_with_owner(%{name: "Acme Inc"}, user)

      organization_id = organization.id

      conn =
        conn
        |> auth_user_conn(user_token)
        |> put_req_header("x-trifle-client-host", "bootstrap-host")
        |> get(~p"/api/v1/bootstrap/me")

      assert %{
               "data" => %{
                 "user" => %{"id" => ^user_id},
                 "organization" => %{"id" => ^organization_id},
                 "membership" => %{"organization_id" => ^organization_id}
               }
             } = json_response(conn, 200)

      assert [token_record] = Accounts.list_user_api_tokens(user)
      assert token_record.last_used_from == "bootstrap-host"
    end

    test "POST /api/v1/bootstrap/organizations creates organization for users without membership",
         %{
           conn: conn,
           user_token: user_token
         } do
      conn =
        conn
        |> auth_user_conn(user_token)
        |> post(~p"/api/v1/bootstrap/organizations", %{"name" => "New Org"})

      assert %{
               "data" => %{
                 "organization" => %{"name" => "New Org"},
                 "membership" => %{"role" => "owner"}
               }
             } = json_response(conn, 201)
    end

    test "can create project/database sources and issue source token", %{
      conn: conn,
      user: user,
      user_token: user_token
    } do
      {:ok, _organization, _membership} =
        Organizations.create_organization_with_owner(%{name: "Acme Inc"}, user)

      cluster = project_cluster_fixture(%{is_default: true})
      file_path = Path.join(System.tmp_dir!(), "bootstrap-api-#{Ecto.UUID.generate()}.sqlite")
      on_exit(fn -> File.rm(file_path) end)

      create_db_conn =
        conn
        |> auth_user_conn(user_token)
        |> post(~p"/api/v1/bootstrap/databases", %{
          "display_name" => "Bootstrap DB",
          "driver" => "sqlite",
          "file_path" => file_path
        })

      assert %{
               "data" => %{
                 "source" => %{"id" => database_id, "type" => "database"}
               }
             } = json_response(create_db_conn, 201)

      setup_conn =
        conn
        |> auth_user_conn(user_token)
        |> post(~p"/api/v1/bootstrap/databases/#{database_id}/setup", %{})

      assert %{
               "data" => %{
                 "source" => %{"id" => ^database_id},
                 "setup" => %{"status" => status}
               }
             } = json_response(setup_conn, 200)

      assert status in ["success", "pending"]

      create_project_conn =
        conn
        |> auth_user_conn(user_token)
        |> post(~p"/api/v1/bootstrap/projects", %{
          "name" => "Bootstrap Project",
          "project_cluster_id" => cluster.id
        })

      assert %{
               "data" => %{
                 "source" => %{"id" => project_id, "type" => "project"}
               }
             } = json_response(create_project_conn, 201)

      token_conn =
        conn
        |> auth_user_conn(user_token)
        |> post(~p"/api/v1/bootstrap/source-tokens", %{
          "source_type" => "project",
          "source_id" => project_id,
          "name" => "Project Write",
          "read" => true,
          "write" => true
        })

      assert %{
               "data" => %{
                 "token" => %{"value" => source_token, "read" => true, "write" => true},
                 "source" => %{"id" => ^project_id, "type" => "project"}
               }
             } = json_response(token_conn, 201)

      assert is_binary(source_token)

      list_conn =
        conn
        |> auth_user_conn(user_token)
        |> get(~p"/api/v1/bootstrap/sources")

      assert %{
               "data" => %{
                 "projects" => projects,
                 "databases" => databases,
                 "membership" => %{"organization_id" => _organization_id}
               }
             } = json_response(list_conn, 200)

      assert Enum.any?(projects, &(&1["id"] == project_id))
      assert Enum.any?(databases, &(&1["id"] == database_id))
    end
  end

  defp api_conn(conn) do
    put_req_header(conn, "accept", "application/json")
  end

  defp auth_user_conn(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
