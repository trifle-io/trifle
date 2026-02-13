defmodule Trifle.OrganizationsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Trifle.Organizations` context.
  """

  alias Trifle.AccountsFixtures
  alias Trifle.Organizations.Project

  @doc """
  Generate a project.
  """
  def project_fixture(attrs \\ %{}) do
    user = Map.get(attrs, :user) || Map.get(attrs, "user") || AccountsFixtures.user_fixture()
    existing_membership = Trifle.Organizations.get_membership_for_user(user)

    organization =
      Map.get(attrs, :organization) ||
        Map.get(attrs, "organization") ||
        (existing_membership && existing_membership.organization) ||
        organization_fixture(%{user: user})

    membership =
      existing_membership ||
        Trifle.Organizations.get_membership_for_org(organization, user) ||
        case Trifle.Organizations.create_membership(organization, user, "owner") do
          {:ok, membership} -> membership
          _ -> nil
        end

    project_cluster =
      Map.get(attrs, :project_cluster) ||
        Map.get(attrs, "project_cluster") ||
        project_cluster_fixture()

    attrs =
      attrs
      |> Map.delete(:user)
      |> Map.delete("user")
      |> Map.delete(:organization)
      |> Map.delete("organization")
      |> Map.delete(:project_cluster)
      |> Map.delete("project_cluster")
      |> Enum.into(%{
        user: user,
        project_cluster_id: project_cluster.id,
        beginning_of_week: 42,
        name: "some name",
        time_zone: "Etc/UTC",
        granularities: ["1m", "1h", "1d"],
        expire_after: Project.basic_retention_seconds(),
        default_timeframe: "7d",
        default_granularity: "1h"
      })

    {:ok, project} = Trifle.Organizations.create_project_for_membership(attrs, membership, user)

    project
  end

  @doc """
  Generate a project cluster.
  """
  def project_cluster_fixture(attrs \\ %{}) do
    code =
      Map.get(attrs, :code) ||
        Map.get(attrs, "code") ||
        "test-#{System.unique_integer([:positive])}"

    attrs =
      attrs
      |> Map.put(:code, code)
      |> Enum.into(%{
        name: "Test Cluster",
        driver: "mongo",
        status: "active",
        visibility: "public",
        is_default: false,
        region: "test",
        host: "localhost",
        port: 27017,
        database_name: "trifle_test",
        config: %{"collection_name" => "trifle_stats"}
      })

    {:ok, cluster} = Trifle.Organizations.create_project_cluster(attrs)

    cluster
  end

  @doc """
  Generate a project_token.
  """
  def project_token_fixture(attrs \\ %{}) do
    project =
      Map.get(attrs, :project) || Map.get(attrs, "project") || project_fixture()

    attrs =
      attrs
      |> Map.delete(:project)
      |> Map.delete("project")
      |> Enum.into(%{
        project: project,
        name: "some name",
        read: true,
        write: true
      })

    {:ok, project_token} = Trifle.Organizations.create_project_token(attrs)

    project_token
  end

  @doc """
  Generate an organization.
  """
  def organization_fixture(attrs \\ %{}) do
    user = Map.get(attrs, :user) || Map.get(attrs, "user") || AccountsFixtures.user_fixture()

    attrs =
      attrs
      |> Map.delete(:user)
      |> Map.delete("user")
      |> Enum.into(%{
        name: "some organization"
      })

    {:ok, organization, _membership} =
      Trifle.Organizations.create_organization_with_owner(attrs, user)

    organization
  end

  @doc """
  Generate a database.
  """
  def database_fixture(attrs \\ %{}) do
    organization =
      Map.get(attrs, :organization) || Map.get(attrs, "organization") || organization_fixture()

    file_path =
      Map.get(attrs, :file_path) ||
        Map.get(attrs, "file_path") ||
        Path.join(System.tmp_dir!(), "trifle-db-#{Ecto.UUID.generate()}.sqlite")

    attrs =
      attrs
      |> Map.delete(:organization)
      |> Map.delete("organization")
      |> Enum.into(%{
        display_name: "some database",
        driver: "sqlite",
        file_path: file_path
      })

    {:ok, database} = Trifle.Organizations.create_database_for_org(organization, attrs)

    database
  end

  @doc """
  Generate a database_token.
  """
  def database_token_fixture(attrs \\ %{}) do
    database = Map.get(attrs, :database) || Map.get(attrs, "database") || database_fixture()

    attrs =
      attrs
      |> Map.delete(:database)
      |> Map.delete("database")
      |> Enum.into(%{
        database: database,
        name: "some name"
      })

    {:ok, database_token} = Trifle.Organizations.create_database_token(attrs)

    database_token
  end
end
