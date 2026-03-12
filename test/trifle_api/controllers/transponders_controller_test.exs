defmodule TrifleApi.TranspondersControllerTest do
  use TrifleApp.ConnCase

  import Trifle.AccountsFixtures
  import Trifle.OrganizationsFixtures
  import TrifleApi.TestHelpers

  alias Trifle.Organizations

  setup do
    user = user_fixture()

    {:ok, organization, _membership} =
      Organizations.create_organization_with_owner(%{name: "Acme Inc"}, user)

    file_path = Path.join(System.tmp_dir!(), "trifle-api-#{Ecto.UUID.generate()}.sqlite")

    {:ok, database} =
      Organizations.create_database_for_org(organization, %{
        display_name: "API DB",
        driver: "sqlite",
        file_path: file_path
      })

    project = project_fixture(%{user: user})

    database_token =
      create_scoped_token!(user, organization.id, :database, database.id, true, false)

    read_project_token =
      create_scoped_token!(user, organization.id, :project, project.id, true, false)

    write_project_token =
      create_scoped_token!(user, organization.id, :project, project.id, false, true)

    on_exit(fn -> File.rm(file_path) end)

    {
      :ok,
      database: database,
      database_token: database_token,
      project: project,
      read_project_token: read_project_token,
      write_project_token: write_project_token
    }
  end

  describe "GET /api/v1/transponders" do
    test "returns 401 without token", %{conn: conn} do
      conn = conn |> api_conn() |> get(~p"/api/v1/transponders")

      assert %{"errors" => %{"detail" => "Bad token"}} = json_response(conn, 401)
    end

    test "returns transponders for database tokens", %{
      conn: conn,
      database: database,
      database_token: token
    } do
      {:ok, _} =
        Organizations.create_transponder_for_database(
          database,
          expression_attrs("Total", "db.total")
        )

      conn =
        conn
        |> api_conn()
        |> auth_conn(token, database.id)
        |> get(~p"/api/v1/transponders")

      assert %{"data" => [data]} = json_response(conn, 200)
      assert data["name"] == "Total"
      assert data["config"]["response"] == "derived.total"
      refute Map.has_key?(data, "type")
    end
  end

  describe "POST /api/v1/transponders" do
    test "creates transponder for database tokens", %{
      conn: conn,
      database_token: token,
      database: database
    } do
      conn =
        conn
        |> api_conn()
        |> auth_conn(token, database.id)
        |> post(~p"/api/v1/transponders", expression_payload("API Total", "metrics.total"))

      assert %{"data" => data} = json_response(conn, 201)
      assert data["name"] == "API Total"
      assert data["source_type"] == "database"
      assert data["config"]["response"] == "derived.total"
      refute Map.has_key?(data, "type")
    end

    test "creates transponder for project tokens", %{
      conn: conn,
      write_project_token: token,
      project: project
    } do
      conn =
        conn
        |> api_conn()
        |> auth_conn(token, project.id)
        |> post(~p"/api/v1/transponders", expression_payload("API Total", "metrics.total"))

      assert %{"data" => data} = json_response(conn, 201)
      assert data["name"] == "API Total"
      assert data["source_type"] == "project"
      assert data["config"]["response"] == "derived.total"
    end
  end

  describe "PUT /api/v1/transponders/:id" do
    test "allows read-only project tokens", %{
      conn: conn,
      project: project,
      read_project_token: token
    } do
      {:ok, transponder} =
        Organizations.create_transponder_for_project(
          project,
          expression_attrs("Total", "proj.total")
        )

      conn =
        conn
        |> api_conn()
        |> auth_conn(token, project.id)
        |> put(~p"/api/v1/transponders/#{transponder.id}", %{"name" => "Updated"})

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == transponder.id
      assert data["name"] == "Updated"
    end

    test "updates transponders for project tokens", %{
      conn: conn,
      project: project,
      write_project_token: token
    } do
      {:ok, transponder} =
        Organizations.create_transponder_for_project(
          project,
          expression_attrs("Total", "proj.total")
        )

      conn =
        conn
        |> api_conn()
        |> auth_conn(token, project.id)
        |> put(~p"/api/v1/transponders/#{transponder.id}", %{
          "config" => %{
            "paths" => ["metrics.sum", "metrics.count"],
            "expression" => "a / b",
            "response" => "metrics.average"
          }
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert data["config"]["response"] == "metrics.average"
    end
  end

  describe "DELETE /api/v1/transponders/:id" do
    test "deletes transponders for project tokens", %{
      conn: conn,
      project: project,
      write_project_token: token
    } do
      {:ok, transponder} =
        Organizations.create_transponder_for_project(
          project,
          expression_attrs("Total", "proj.total")
        )

      conn =
        conn
        |> api_conn()
        |> auth_conn(token, project.id)
        |> delete(~p"/api/v1/transponders/#{transponder.id}")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == transponder.id
    end
  end

  defp expression_payload(name, key) do
    %{
      "name" => name,
      "key" => key,
      "config" => %{
        "paths" => ["metrics.total"],
        "expression" => "a",
        "response" => "derived.total"
      }
    }
  end

  defp expression_attrs(name, key) do
    %{
      "name" => name,
      "key" => key,
      "config" => %{
        "paths" => ["metrics.total"],
        "expression" => "a",
        "response" => "derived.total"
      }
    }
  end

  defp api_conn(conn) do
    put_req_header(conn, "accept", "application/json")
  end

  defp auth_conn(conn, token, source_id) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("x-trifle-source-id", to_string(source_id))
  end
end
