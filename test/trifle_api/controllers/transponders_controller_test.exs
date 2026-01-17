defmodule TrifleApi.TranspondersControllerTest do
  use TrifleApp.ConnCase

  import Trifle.AccountsFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations
  alias Trifle.Organizations.Transponder
  alias Trifle.Repo

  @expression_type "Trifle.Stats.Transponder.Expression"

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

    {:ok, database_token} =
      Organizations.create_database_token(%{database: database, name: "Read"})

    project = project_fixture(%{user: user})

    {:ok, read_project_token} =
      Organizations.create_project_token(%{
        project: project,
        name: "Read",
        read: true,
        write: false
      })

    {:ok, write_project_token} =
      Organizations.create_project_token(%{
        project: project,
        name: "Write",
        read: false,
        write: true
      })

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

    test "allows write-only project tokens", %{conn: conn, write_project_token: token} do
      conn =
        conn
        |> api_conn()
        |> auth_conn(token.token)
        |> get(~p"/api/v1/transponders")

      assert %{"data" => _data} = json_response(conn, 200)
    end

    test "returns expression transponders for database tokens", %{
      conn: conn,
      database: database,
      database_token: token
    } do
      {:ok, _} =
        Organizations.create_transponder_for_database(
          database,
          expression_attrs("Total", "db.total")
        )

      _legacy =
        legacy_transponder!(%{
          name: "Legacy Add",
          key: "db.add",
          type: "Trifle.Stats.Transponder.Add",
          config: %{"path1" => "metrics.a", "path2" => "metrics.b"},
          source_type: "database",
          source_id: database.id,
          database_id: database.id,
          organization_id: database.organization_id
        })

      conn =
        conn
        |> api_conn()
        |> auth_conn(token.token)
        |> get(~p"/api/v1/transponders")

      assert %{"data" => data} = json_response(conn, 200)
      assert length(data) == 1
      assert Enum.all?(data, fn item -> item["type"] == @expression_type end)
    end
  end

  describe "POST /api/v1/transponders" do
    test "creates expression transponder for database tokens", %{
      conn: conn,
      database_token: token
    } do
      conn =
        conn
        |> api_conn()
        |> auth_conn(token.token)
        |> post(~p"/api/v1/transponders", expression_payload("API Total", "metrics.total"))

      assert %{"data" => data} = json_response(conn, 201)
      assert data["name"] == "API Total"
      assert data["type"] == @expression_type
      assert data["source_type"] == "database"
    end

    test "creates expression transponder for project tokens", %{
      conn: conn,
      write_project_token: token
    } do
      conn =
        conn
        |> api_conn()
        |> auth_conn(token.token)
        |> post(~p"/api/v1/transponders", expression_payload("API Total", "metrics.total"))

      assert %{"data" => data} = json_response(conn, 201)
      assert data["name"] == "API Total"
      assert data["type"] == @expression_type
      assert data["source_type"] == "project"
    end

    test "rejects unsupported transponder types", %{conn: conn, write_project_token: token} do
      payload =
        expression_payload("Bad Type", "metrics.total")
        |> Map.put("type", "Trifle.Stats.Transponder.Add")

      conn =
        conn
        |> api_conn()
        |> auth_conn(token.token)
        |> post(~p"/api/v1/transponders", payload)

      assert %{"errors" => %{"detail" => "Unsupported transponder type"}} =
               json_response(conn, 422)
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
        |> auth_conn(token.token)
        |> put(~p"/api/v1/transponders/#{transponder.id}", %{"name" => "Updated"})

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == transponder.id
      assert data["name"] == "Updated"
    end

    test "updates expression transponders for project tokens", %{
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
        |> auth_conn(token.token)
        |> put(~p"/api/v1/transponders/#{transponder.id}", %{"name" => "Updated"})

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == transponder.id
      assert data["name"] == "Updated"
    end

    test "rejects non-expression transponders", %{
      conn: conn,
      project: project,
      write_project_token: token
    } do
      transponder =
        legacy_transponder!(%{
          name: "Legacy Add",
          key: "proj.add",
          type: "Trifle.Stats.Transponder.Add",
          config: %{"path1" => "metrics.a", "path2" => "metrics.b"},
          source_type: "project",
          source_id: project.id
        })

      conn =
        conn
        |> api_conn()
        |> auth_conn(token.token)
        |> put(~p"/api/v1/transponders/#{transponder.id}", %{"name" => "Updated"})

      assert %{"errors" => %{"detail" => "Unsupported transponder type"}} =
               json_response(conn, 422)
    end
  end

  defp expression_payload(name, key) do
    %{
      "name" => name,
      "key" => key,
      "config" => %{
        "paths" => ["metrics.total"],
        "expression" => "a",
        "response_path" => "derived.total"
      }
    }
  end

  defp expression_attrs(name, key) do
    %{
      "name" => name,
      "key" => key,
      "type" => @expression_type,
      "config" => %{
        "paths" => ["metrics.total"],
        "expression" => "a",
        "response_path" => "derived.total"
      }
    }
  end

  defp legacy_transponder!(attrs) do
    %Transponder{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
  end

  defp api_conn(conn) do
    put_req_header(conn, "accept", "application/json")
  end

  defp auth_conn(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
