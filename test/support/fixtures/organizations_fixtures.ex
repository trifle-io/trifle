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
end
