defmodule Trifle.OrganizationFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Trifle.Organizations` context.
  """

  @doc """
  Generate a project_token.
  """
  def project_token_fixture(attrs \\ %{}) do
    Trifle.OrganizationsFixtures.project_token_fixture(attrs)
  end
end
