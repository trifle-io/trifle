defmodule TrifleApi.BootstrapControllerTest do
  use TrifleApp.ConnCase

  import Trifle.AccountsFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Accounts
  alias Trifle.Organizations
  alias Trifle.Organizations.OrganizationApiToken
  alias Trifle.Repo

  setup %{conn: conn} do
    user = user_fixture()

    {:ok, conn: api_conn(conn), user: user}
  end

  describe "POST /api/v1/bootstrap/signup" do
    test "creates organization token and optional organization", %{conn: conn} do
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
                 "organization" => %{"id" => organization_id, "name" => "Bootstrap Org"},
                 "membership" => %{"role" => "owner"}
               }
             } = json_response(conn, 201)

      assert is_binary(token)
      assert String.starts_with?(token, "trf_oat_")

      created_user = Accounts.get_user_by_email(email)
      assert {:ok, %{token: record}} = Organizations.get_api_token_auth(token)
      assert created_user.id == record.user_id
      assert organization_id == record.organization_id
      assert record.created_by == "trifle-cli-test"
      assert record.created_from == "agent-host"
    end

    test "rolls back user creation when organization creation fails", %{conn: conn} do
      email = unique_user_email()
      invalid_org_name = String.duplicate("x", 256)

      conn =
        post(conn, ~p"/api/v1/bootstrap/signup", %{
          "email" => email,
          "password" => valid_user_password(),
          "organization_name" => invalid_org_name
        })

      assert %{"errors" => %{"name" => _}} = json_response(conn, 422)
      assert Accounts.get_user_by_email(email) == nil
    end
  end

  describe "POST /api/v1/bootstrap/login" do
    test "issues new organization token for valid credentials", %{conn: conn, user: user} do
      {:ok, organization, _membership} =
        Organizations.create_organization_with_owner(%{name: "Acme Inc"}, user)

      user_id = user.id
      organization_id = organization.id

      conn =
        post(conn, ~p"/api/v1/bootstrap/login", %{
          "email" => user.email,
          "password" => valid_user_password()
        })

      assert %{
               "data" => %{
                 "user" => %{"id" => ^user_id},
                 "token" => %{"value" => token},
                 "organization" => %{"id" => ^organization_id},
                 "membership" => %{"organization_id" => ^organization_id}
               }
             } = json_response(conn, 201)

      assert is_binary(token)
      assert String.starts_with?(token, "trf_oat_")
    end
  end

  describe "authenticated bootstrap endpoints" do
    setup %{user: user} do
      {:ok, organization, _membership} =
        Organizations.create_organization_with_owner(%{name: "Acme Inc"}, user)

      {:ok, _token_record, user_token} =
        Organizations.create_organization_api_token(user, %{
          name: "Bootstrap",
          organization_id: organization.id
        })

      {:ok, organization: organization, user_token: user_token}
    end

    test "GET /api/v1/bootstrap/me returns user and membership context", %{
      conn: conn,
      user: user,
      organization: organization,
      user_token: user_token
    } do
      user_id = user.id
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

      token_hash = OrganizationApiToken.hash_token(user_token)
      token_record = Repo.get_by!(OrganizationApiToken, token_hash: token_hash)
      assert token_record.last_used_from == "bootstrap-host"
    end

    test "POST /api/v1/bootstrap/organizations creates organization for users without membership",
         %{
           conn: conn
         } do
      user = user_fixture()
      user_token = create_unscoped_token!(user)

      conn =
        conn
        |> auth_user_conn(user_token)
        |> post(~p"/api/v1/bootstrap/organizations", %{"name" => "New Org"})

      assert %{
               "data" => %{
                 "organization" => %{"id" => organization_id, "name" => "New Org"},
                 "membership" => %{"role" => "owner"}
               }
             } = json_response(conn, 201)

      assert {:ok, %{token: token_record}} = Organizations.get_api_token_auth(user_token)
      assert token_record.organization_id == organization_id
    end

    test "can list/create/update/delete organization tokens", %{
      conn: conn,
      user_token: user_token
    } do
      create_conn =
        conn
        |> auth_user_conn(user_token)
        |> post(~p"/api/v1/bootstrap/tokens", %{
          "name" => "Automation token",
          "wildcard_read" => true,
          "wildcard_write" => false
        })

      assert %{
               "data" => %{
                 "token" => %{
                   "id" => token_id,
                   "value" => created_value,
                   "name" => "Automation token",
                   "permissions" => %{
                     "wildcard" => %{"read" => true, "write" => false}
                   }
                 }
               }
             } = json_response(create_conn, 201)

      assert is_binary(created_value)
      assert String.starts_with?(created_value, "trf_oat_")

      list_conn =
        conn
        |> auth_user_conn(user_token)
        |> get(~p"/api/v1/bootstrap/tokens")

      assert %{"data" => %{"tokens" => tokens}} = json_response(list_conn, 200)
      assert Enum.any?(tokens, &(&1["id"] == token_id))

      update_conn =
        conn
        |> auth_user_conn(user_token)
        |> put(~p"/api/v1/bootstrap/tokens/#{token_id}", %{
          "wildcard_read" => true,
          "wildcard_write" => true
        })

      assert %{
               "data" => %{
                 "token" => %{
                   "id" => ^token_id,
                   "permissions" => %{
                     "wildcard" => %{"read" => true, "write" => true}
                   }
                 }
               }
             } = json_response(update_conn, 200)

      delete_conn =
        conn
        |> auth_user_conn(user_token)
        |> delete(~p"/api/v1/bootstrap/tokens/#{token_id}")

      assert %{"data" => %{"id" => ^token_id}} = json_response(delete_conn, 200)
    end

    test "token create supports scoped source grants", %{
      conn: conn,
      user: user,
      user_token: user_token
    } do
      project = project_fixture(%{user: user})

      create_conn =
        conn
        |> auth_user_conn(user_token)
        |> post(~p"/api/v1/bootstrap/tokens", %{
          "source_type" => "project",
          "source_id" => project.id,
          "name" => "Scoped token",
          "read" => true,
          "write" => true
        })

      assert %{
               "data" => %{
                 "token" => %{
                   "permissions" => %{
                     "sources" => sources
                   }
                 }
               }
             } = json_response(create_conn, 201)

      assert map_size(sources) == 1
      assert Map.has_key?(sources, "project:#{project.id}")
    end

    test "database setup returns validation error for invalid source id", %{
      conn: conn,
      user_token: user_token
    } do
      conn =
        conn
        |> auth_user_conn(user_token)
        |> post(~p"/api/v1/bootstrap/databases/not-a-uuid/setup", %{})

      assert %{"errors" => %{"source_id" => source_id_errors}} = json_response(conn, 422)
      assert "is invalid" in source_id_errors
    end

    test "auto-grants created sources to current token and can issue scoped token", %{
      conn: conn,
      user_token: user_token
    } do
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

      assert {:ok, %{token: bootstrap_token_record}} =
               Organizations.get_api_token_auth(user_token)

      assert Organizations.token_has_permission?(
               bootstrap_token_record.permissions,
               :database,
               database_id,
               :read
             )

      refute Organizations.token_has_permission?(
               bootstrap_token_record.permissions,
               :database,
               database_id,
               :write
             )

      assert Organizations.token_has_permission?(
               bootstrap_token_record.permissions,
               :project,
               project_id,
               :read
             )

      assert Organizations.token_has_permission?(
               bootstrap_token_record.permissions,
               :project,
               project_id,
               :write
             )

      token_conn =
        conn
        |> auth_user_conn(user_token)
        |> post(~p"/api/v1/bootstrap/tokens", %{
          "source_type" => "project",
          "source_id" => project_id,
          "name" => "Project Write Token",
          "read" => true,
          "write" => true,
          "wildcard_read" => false,
          "wildcard_write" => false
        })

      assert %{
               "data" => %{
                 "token" => %{
                   "value" => source_token,
                   "permissions" => %{
                     "sources" => sources
                   }
                 }
               }
             } = json_response(token_conn, 201)

      assert is_binary(source_token)
      assert is_map(sources)

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

    test "can upload sqlite file when creating bootstrap database source", %{
      conn: conn,
      organization: organization,
      user_token: user_token
    } do
      temp_input_path =
        Path.join(System.tmp_dir!(), "bootstrap-upload-#{Ecto.UUID.generate()}.sqlite")

      File.write!(temp_input_path, "sqlite")
      on_exit(fn -> File.rm(temp_input_path) end)

      upload = %Plug.Upload{
        path: temp_input_path,
        filename: "metrics.sqlite",
        content_type: "application/octet-stream"
      }

      create_db_conn =
        conn
        |> auth_user_conn(user_token)
        |> post(~p"/api/v1/bootstrap/databases", %{
          "display_name" => "Bootstrap Upload DB",
          "driver" => "sqlite",
          "sqlite_file" => upload
        })

      assert %{
               "data" => %{
                 "source" => %{"id" => database_id, "type" => "database"}
               }
             } = json_response(create_db_conn, 201)

      database = Organizations.get_database!(database_id)

      on_exit(fn ->
        _ = Organizations.delete_database(database)
      end)

      assert database.file_path =~ "/organization_#{organization.id}/sqlite/"
      assert File.exists?(database.file_path)
    end

    test "rejects invalid sqlite upload extension", %{
      conn: conn,
      user_token: user_token
    } do
      temp_input_path =
        Path.join(System.tmp_dir!(), "bootstrap-upload-#{Ecto.UUID.generate()}.txt")

      File.write!(temp_input_path, "not sqlite")
      on_exit(fn -> File.rm(temp_input_path) end)

      upload = %Plug.Upload{
        path: temp_input_path,
        filename: "metrics.txt",
        content_type: "text/plain"
      }

      conn =
        conn
        |> auth_user_conn(user_token)
        |> post(~p"/api/v1/bootstrap/databases", %{
          "display_name" => "Bootstrap Upload DB",
          "driver" => "sqlite",
          "sqlite_file" => upload
        })

      assert %{"errors" => %{"detail" => detail}} = json_response(conn, 422)
      assert detail =~ "Unsupported SQLite file type"
    end

    test "rejects malformed sqlite upload payload", %{
      conn: conn,
      user_token: user_token
    } do
      conn =
        conn
        |> auth_user_conn(user_token)
        |> post(~p"/api/v1/bootstrap/databases", %{
          "display_name" => "Bootstrap Upload DB",
          "driver" => "sqlite",
          "sqlite_file" => "not-an-upload"
        })

      assert %{"errors" => %{"detail" => detail}} = json_response(conn, 422)
      assert detail == "invalid sqlite_file upload"
    end
  end

  defp api_conn(conn) do
    put_req_header(conn, "accept", "application/json")
  end

  defp auth_user_conn(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  # Intentionally bypasses changeset validation to exercise legacy unscoped-token
  # bootstrap paths where organization_id was not yet bound.
  defp create_unscoped_token!(user) do
    value = OrganizationApiToken.build_token()

    %OrganizationApiToken{
      name: "Bootstrap legacy token",
      token_hash: OrganizationApiToken.hash_token(value),
      token_last5: OrganizationApiToken.token_last5(value),
      permissions: Organizations.normalize_token_permissions(%{}),
      user_id: user.id
    }
    |> Repo.insert!()

    value
  end
end
