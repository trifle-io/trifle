defmodule Trifle.OrganizationsTest do
  use Trifle.DataCase

  alias Trifle.Organizations

  describe "projects" do
    alias Trifle.Organizations.Project

    import Trifle.OrganizationsFixtures

    @invalid_attrs %{beginning_of_week: nil, name: nil, time_zone: nil, granularities: nil}

    test "list_projects/0 returns all projects" do
      project = project_fixture()
      assert Organizations.list_projects() == [project]
    end

    test "get_project!/1 returns the project with given id" do
      project = project_fixture()
      assert Organizations.get_project!(project.id) == project
    end

    test "create_project/1 with valid data creates a project" do
      valid_attrs = %{
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

    test "create_project/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Organizations.create_project(@invalid_attrs)
    end

    test "update_project/2 with valid data updates the project" do
      project = project_fixture()

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

    test "update_project/2 with invalid data returns error changeset" do
      project = project_fixture()
      assert {:error, %Ecto.Changeset{}} = Organizations.update_project(project, @invalid_attrs)
      assert project == Organizations.get_project!(project.id)
    end

    test "delete_project/1 deletes the project" do
      project = project_fixture()
      assert {:ok, %Project{}} = Organizations.delete_project(project)
      assert_raise Ecto.NoResultsError, fn -> Organizations.get_project!(project.id) end
    end

    test "change_project/1 returns a project changeset" do
      project = project_fixture()
      assert %Ecto.Changeset{} = Organizations.change_project(project)
    end
  end

  describe "project transponders" do
    import Trifle.OrganizationsFixtures

    test "create_transponder_for_project/2 sets project source" do
      project = project_fixture()

      attrs = %{
        "name" => "Project Total",
        "key" => "metrics::total",
        "type" => "Trifle.Stats.Transponder.Add",
        "config" => %{"path1" => "foo", "path2" => "bar"}
      }

      {:ok, transponder} = Organizations.create_transponder_for_project(project, attrs)

      assert transponder.source_type == "project"
      assert transponder.source_id == project.id
      assert transponder.organization_id == nil
    end

    test "list_transponders_for_project/1 returns transponders for project" do
      project = project_fixture()

      {:ok, transponder} =
        Organizations.create_transponder_for_project(project, %{
          "name" => "Project Ratio",
          "key" => "proj::ratio",
          "type" => "Trifle.Stats.Transponder.Ratio",
          "config" => %{"path1" => "foo", "path2" => "bar"}
        })

      assert Organizations.list_transponders_for_project(project) == [transponder]
    end

    test "get_transponder_for_source!/2 fetches project transponder" do
      project = project_fixture()

      {:ok, transponder} =
        Organizations.create_transponder_for_project(project, %{
          "name" => "Project Mean",
          "key" => "proj::mean",
          "type" => "Trifle.Stats.Transponder.Mean",
          "config" => %{"path" => "foo"}
        })

      assert Organizations.get_transponder_for_source!(project, transponder.id).id ==
               transponder.id
    end
  end

  describe "project_tokens" do
    alias Trifle.Organizations.ProjectToken

    import Trifle.OrganizationsFixtures

    @invalid_attrs %{name: nil, read: nil, token: nil, write: nil}

    test "list_project_tokens/0 returns all project_tokens" do
      project_token = project_token_fixture()
      assert Organizations.list_project_tokens() == [project_token]
    end

    test "get_project_token!/1 returns the project_token with given id" do
      project_token = project_token_fixture()
      assert Organizations.get_project_token!(project_token.id) == project_token
    end

    test "create_project_token/1 with valid data creates a project_token" do
      valid_attrs = %{name: "some name", read: true, token: "some token", write: true}

      assert {:ok, %ProjectToken{} = project_token} =
               Organizations.create_project_token(valid_attrs)

      assert project_token.name == "some name"
      assert project_token.read == true
      assert project_token.token == "some token"
      assert project_token.write == true
    end

    test "create_project_token/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Organizations.create_project_token(@invalid_attrs)
    end

    test "update_project_token/2 with valid data updates the project_token" do
      project_token = project_token_fixture()

      update_attrs = %{
        name: "some updated name",
        read: false,
        token: "some updated token",
        write: false
      }

      assert {:ok, %ProjectToken{} = project_token} =
               Organizations.update_project_token(project_token, update_attrs)

      assert project_token.name == "some updated name"
      assert project_token.read == false
      assert project_token.token == "some updated token"
      assert project_token.write == false
    end

    test "update_project_token/2 with invalid data returns error changeset" do
      project_token = project_token_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Organizations.update_project_token(project_token, @invalid_attrs)

      assert project_token == Organizations.get_project_token!(project_token.id)
    end

    test "delete_project_token/1 deletes the project_token" do
      project_token = project_token_fixture()
      assert {:ok, %ProjectToken{}} = Organizations.delete_project_token(project_token)

      assert_raise Ecto.NoResultsError, fn ->
        Organizations.get_project_token!(project_token.id)
      end
    end

    test "change_project_token/1 returns a project_token changeset" do
      project_token = project_token_fixture()
      assert %Ecto.Changeset{} = Organizations.change_project_token(project_token)
    end
  end
end
