defmodule TrifleWeb.RegistrationConfig do
  @moduledoc """
  Configuration helpers for user registration functionality.

  This module provides utilities to check whether user registration is enabled
  based on environment variables. This allows for runtime configuration of
  registration availability.
  """

  @doc """
  Checks if user registration is enabled based on the REGISTRATION_ENABLED environment variable.

  Defaults to true if the environment variable is not set.

  ## Examples

      iex> TrifleWeb.RegistrationConfig.enabled?()
      true
      
      # When REGISTRATION_ENABLED=false
      iex> TrifleWeb.RegistrationConfig.enabled?()
      false
  """
  def enabled? do
    System.get_env("REGISTRATION_ENABLED", "true") == "true"
  end

  @doc """
  Returns the registration URL path if registration is enabled, otherwise returns nil.

  This is useful for conditional navigation links.

  ## Examples

      iex> TrifleWeb.RegistrationConfig.registration_path()
      "/users/register"
      
      # When registration is disabled
      iex> TrifleWeb.RegistrationConfig.registration_path()
      nil
  """
  def registration_path do
    if enabled?(), do: "/users/register", else: nil
  end
end
