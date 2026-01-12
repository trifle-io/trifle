defmodule Trifle.OrganizationsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Trifle.Organizations` context.
  """

  alias Trifle.AccountsFixtures

  @doc """
  Generate a project.
  """
  def project_fixture(attrs \\ %{}) do
    user = Map.get(attrs, :user) || Map.get(attrs, "user") || AccountsFixtures.user_fixture()

    attrs =
      attrs
      |> Map.delete(:user)
      |> Map.delete("user")
      |> Enum.into(%{
        user: user,
        beginning_of_week: 42,
        name: "some name",
        time_zone: "Etc/UTC",
        granularities: ["1m", "1h", "1d"],
        expire_after: 86_400,
        default_timeframe: "7d",
        default_granularity: "1h"
      })

    {:ok, project} = Trifle.Organizations.create_project(attrs)

    project
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
