defmodule Trifle.OrganizationsTest do
  use Trifle.DataCase

  alias Trifle.Organizations

  describe "projects" do
    alias Trifle.Organizations.Project

    import Trifle.OrganizationsFixtures
    import Trifle.AccountsFixtures

    @invalid_attrs %{beginning_of_week: nil, name: nil, time_zone: nil, granularities: nil}

    setup do
      %{user: user_fixture()}
    end

    test "list_projects/0 returns all projects", %{user: user} do
      project = project_fixture(%{user: user})
      assert Enum.map(Organizations.list_projects(), & &1.id) == [project.id]
    end

    test "get_project!/1 returns the project with given id", %{user: user} do
      project = project_fixture(%{user: user})
      assert Organizations.get_project!(project.id).id == project.id
    end

    test "create_project/1 with valid data creates a project", %{user: user} do
      valid_attrs = %{
        user: user,
        beginning_of_week: 42,
        name: "some name",
        time_zone: "Etc/UTC",
        granularities: ["1m", "1h"],
        expire_after: 3_600,
        default_timeframe: "24h",
        default_granularity: "1h"
      }

      assert {:ok, %Project{} = project} = Organizations.create_project(valid_attrs)
      assert project.beginning_of_week == 42
      assert project.name == "some name"
      assert project.time_zone == "Etc/UTC"
      assert project.granularities == ["1m", "1h"]
      assert project.default_granularity == "1h"
      assert project.default_timeframe == "24h"
      assert project.expire_after == 3_600
    end

    test "create_project/1 with invalid data returns error changeset", %{user: user} do
      assert {:error, %Ecto.Changeset{}} =
               Organizations.create_project(Map.put(@invalid_attrs, :user, user))
    end

    test "update_project/2 with valid data updates the project", %{user: user} do
      project = project_fixture(%{user: user})

      update_attrs = %{
        beginning_of_week: 43,
        name: "some updated name",
        time_zone: "America/New_York",
        granularities: ["1h", "1d"],
        expire_after: 86_400,
        default_timeframe: "7d",
        default_granularity: "1d"
      }

      assert {:ok, %Project{} = project} = Organizations.update_project(project, update_attrs)
      assert project.beginning_of_week == 43
      assert project.name == "some updated name"
      assert project.time_zone == "America/New_York"
      assert project.granularities == ["1h", "1d"]
      assert project.default_granularity == "1d"
      assert project.default_timeframe == "7d"
      assert project.expire_after == 86_400
    end

    test "update_project/2 with invalid data returns error changeset", %{user: user} do
      project = project_fixture(%{user: user})
      assert {:error, %Ecto.Changeset{}} = Organizations.update_project(project, @invalid_attrs)
      assert Organizations.get_project!(project.id).id == project.id
    end

    test "delete_project/1 deletes the project", %{user: user} do
      project = project_fixture(%{user: user})
      assert {:ok, %Project{}} = Organizations.delete_project(project)
      assert_raise Ecto.NoResultsError, fn -> Organizations.get_project!(project.id) end
    end

    test "change_project/1 returns a project changeset", %{user: user} do
      project = project_fixture(%{user: user})
      assert %Ecto.Changeset{} = Organizations.change_project(project)
    end
  end

  describe "project transponders" do
    import Trifle.OrganizationsFixtures
    import Trifle.AccountsFixtures

    setup do
      %{user: user_fixture()}
    end

    test "create_transponder_for_project/2 sets project source", %{user: user} do
      project = project_fixture(%{user: user})

      attrs = %{
        "name" => "Project Total",
        "key" => "metrics::total",
        "type" => "Trifle.Stats.Transponder.Expression",
        "config" => %{
          "paths" => ["foo"],
          "expression" => "a",
          "response_path" => "total"
        }
      }

      {:ok, transponder} = Organizations.create_transponder_for_project(project, attrs)

      assert transponder.source_type == "project"
      assert transponder.source_id == project.id
      assert transponder.organization_id == nil
    end

    test "list_transponders_for_project/1 returns transponders for project", %{user: user} do
      project = project_fixture(%{user: user})

      {:ok, transponder} =
        Organizations.create_transponder_for_project(project, %{
          "name" => "Project Ratio",
          "key" => "proj::ratio",
          "type" => "Trifle.Stats.Transponder.Expression",
          "config" => %{
            "paths" => ["foo"],
            "expression" => "a",
            "response_path" => "ratio"
          }
        })

      assert Organizations.list_transponders_for_project(project) == [transponder]
    end

    test "get_transponder_for_source!/2 fetches project transponder", %{user: user} do
      project = project_fixture(%{user: user})

      {:ok, transponder} =
        Organizations.create_transponder_for_project(project, %{
          "name" => "Project Mean",
          "key" => "proj::mean",
          "type" => "Trifle.Stats.Transponder.Expression",
          "config" => %{
            "paths" => ["foo"],
            "expression" => "a",
            "response_path" => "mean"
          }
        })

      assert Organizations.get_transponder_for_source!(project, transponder.id).id ==
               transponder.id
    end
  end

  describe "project_tokens" do
    alias Trifle.Organizations.ProjectToken

    import Trifle.OrganizationsFixtures
    import Trifle.AccountsFixtures

    @invalid_attrs %{name: nil, read: nil, token: nil, write: nil}

    setup do
      %{user: user_fixture()}
    end

    test "list_project_tokens/0 returns all project_tokens", %{user: user} do
      project = project_fixture(%{user: user})
      project_token = project_token_fixture(%{project: project})
      assert Enum.map(Organizations.list_project_tokens(), & &1.id) == [project_token.id]
    end

    test "get_project_token!/1 returns the project_token with given id", %{user: user} do
      project = project_fixture(%{user: user})
      project_token = project_token_fixture(%{project: project})
      assert Organizations.get_project_token!(project_token.id).id == project_token.id
    end

    test "create_project_token/1 with valid data creates a project_token", %{user: user} do
      project = project_fixture(%{user: user})

      valid_attrs = %{
        project: project,
        name: "some name",
        read: true,
        write: true
      }

      assert {:ok, %ProjectToken{} = project_token} =
               Organizations.create_project_token(valid_attrs)

      assert project_token.name == "some name"
      assert project_token.read == true
      assert is_binary(project_token.token)
      assert project_token.token != ""
      assert project_token.write == true
    end

    test "create_project_token/1 with invalid data returns error changeset", %{user: user} do
      project = project_fixture(%{user: user})

      assert {:error, %Ecto.Changeset{}} =
               Organizations.create_project_token(Map.put(@invalid_attrs, :project, project))
    end

    test "update_project_token/2 with valid data updates the project_token", %{user: user} do
      project = project_fixture(%{user: user})
      project_token = project_token_fixture(%{project: project})
      original_token = project_token.token

      update_attrs = %{
        name: "some updated name",
        read: false,
        write: false
      }

      assert {:ok, %ProjectToken{} = project_token} =
               Organizations.update_project_token(project_token, update_attrs)

      assert project_token.name == "some updated name"
      assert project_token.read == false
      assert project_token.token == original_token
      assert project_token.write == false
    end

    test "update_project_token/2 with invalid data returns error changeset", %{user: user} do
      project = project_fixture(%{user: user})
      project_token = project_token_fixture(%{project: project})

      assert {:error, %Ecto.Changeset{}} =
               Organizations.update_project_token(project_token, @invalid_attrs)

      assert Organizations.get_project_token!(project_token.id).id == project_token.id
    end

    test "delete_project_token/1 deletes the project_token", %{user: user} do
      project = project_fixture(%{user: user})
      project_token = project_token_fixture(%{project: project})
      assert {:ok, %ProjectToken{}} = Organizations.delete_project_token(project_token)

      assert_raise Ecto.NoResultsError, fn ->
        Organizations.get_project_token!(project_token.id)
      end
    end

    test "change_project_token/1 returns a project_token changeset", %{user: user} do
      project = project_fixture(%{user: user})
      project_token = project_token_fixture(%{project: project})
      assert %Ecto.Changeset{} = Organizations.change_project_token(project_token)
    end
  end

  describe "database_tokens" do
    alias Trifle.Organizations.DatabaseToken

    import Trifle.OrganizationsFixtures
    import Trifle.AccountsFixtures

    @invalid_attrs %{name: nil, read: nil, token: nil}

    setup do
      %{user: user_fixture()}
    end

    test "list_database_tokens/0 returns all database_tokens", %{user: _user} do
      database = database_fixture()
      database_token = database_token_fixture(%{database: database})
      assert Enum.map(Organizations.list_database_tokens(), & &1.id) == [database_token.id]
    end

    test "get_database_token!/1 returns the database_token with given id", %{user: _user} do
      database = database_fixture()
      database_token = database_token_fixture(%{database: database})
      assert Organizations.get_database_token!(database_token.id).id == database_token.id
    end

    test "create_database_token/1 with valid data creates a database_token", %{user: _user} do
      database = database_fixture()

      valid_attrs = %{
        database: database,
        name: "some name"
      }

      assert {:ok, %DatabaseToken{} = database_token} =
               Organizations.create_database_token(valid_attrs)

      assert database_token.name == "some name"
      assert database_token.read == true
      assert is_binary(database_token.token)
      assert database_token.token != ""
    end

    test "create_database_token/1 with invalid data returns error changeset", %{user: _user} do
      database = database_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Organizations.create_database_token(Map.put(@invalid_attrs, :database, database))
    end

    test "update_database_token/2 with valid data updates the database_token", %{user: _user} do
      database = database_fixture()
      database_token = database_token_fixture(%{database: database})
      original_token = database_token.token

      update_attrs = %{
        name: "some updated name"
      }

      assert {:ok, %DatabaseToken{} = database_token} =
               Organizations.update_database_token(database_token, update_attrs)

      assert database_token.name == "some updated name"
      assert database_token.read == true
      assert database_token.token == original_token
    end

    test "update_database_token/2 with invalid data returns error changeset", %{user: _user} do
      database = database_fixture()
      database_token = database_token_fixture(%{database: database})

      assert {:error, %Ecto.Changeset{}} =
               Organizations.update_database_token(database_token, @invalid_attrs)

      assert Organizations.get_database_token!(database_token.id).id == database_token.id
    end

    test "delete_database_token/1 deletes the database_token", %{user: _user} do
      database = database_fixture()
      database_token = database_token_fixture(%{database: database})
      assert {:ok, %DatabaseToken{}} = Organizations.delete_database_token(database_token)

      assert_raise Ecto.NoResultsError, fn ->
        Organizations.get_database_token!(database_token.id)
      end
    end

    test "change_database_token/1 returns a database_token changeset", %{user: _user} do
      database = database_fixture()
      database_token = database_token_fixture(%{database: database})
      assert %Ecto.Changeset{} = Organizations.change_database_token(database_token)
    end
  end
end
