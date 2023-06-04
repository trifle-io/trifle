defmodule Trifle.OrganizationFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Trifle.Organization` context.
  """

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
      |> Trifle.Organization.create_project_token()

    project_token
  end
end
