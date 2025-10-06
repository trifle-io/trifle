defmodule Trifle.OrganizationsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Trifle.Organizations` context.
  """

  @doc """
  Generate a project.
  """
  def project_fixture(attrs \\ %{}) do
    {:ok, project} =
      attrs
      |> Enum.into(%{
        beginning_of_week: 42,
        name: "some name",
        time_zone: "Etc/UTC",
        granularities: ["1m", "1h", "1d"],
        expire_after: 86_400,
        default_timeframe: "7d",
        default_granularity: "1h"
      })
      |> Trifle.Organizations.create_project()

    project
  end

  @doc """
  Generate a project_token.
  """
  def project_token_fixture(attrs \\ %{}) do
    {:ok, project_token} =
      attrs
      |> Enum.into(%{
        name: "some name",
        read: true,
        token: "some token",
        write: true
      })
      |> Trifle.Organizations.create_project_token()

    project_token
  end
end
