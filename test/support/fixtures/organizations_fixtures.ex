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
        slug: "some slug",
        time_zone: "some time_zone"
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
