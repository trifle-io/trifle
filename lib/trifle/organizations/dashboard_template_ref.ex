defmodule Trifle.Organizations.DashboardTemplateRef do
  @moduledoc """
  Encodes and parses the polymorphic value stored in `dashboards.template_id`.
  """

  alias Ecto.UUID

  @type kind :: :system | :user
  @type parsed :: {kind(), String.t()}

  @spec encode(kind(), String.t()) :: String.t()
  def encode(:system, key) when is_binary(key), do: "system:#{String.trim(key)}"
  def encode(:user, id) when is_binary(id), do: "user:#{String.trim(id)}"

  @spec normalize(term()) :: term()
  def normalize(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def normalize(value), do: value

  @spec parse(nil | String.t()) :: :none | {:ok, parsed()} | {:error, :invalid_template_id}
  def parse(nil), do: :none

  def parse(value) when is_binary(value) do
    case String.split(String.trim(value), ":", parts: 2) do
      ["system", key] when key != "" -> {:ok, {:system, key}}
      ["user", id] -> parse_user_id(id)
      _ -> {:error, :invalid_template_id}
    end
  end

  def parse(_value), do: {:error, :invalid_template_id}

  defp parse_user_id(id) do
    case UUID.cast(id) do
      {:ok, uuid} -> {:ok, {:user, uuid}}
      :error -> {:error, :invalid_template_id}
    end
  end
end
