defmodule Trifle.Monitors.Execution do
  @moduledoc """
  Represents a single execution (trigger) of a monitor.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Trifle.Monitors.Monitor

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "monitor_executions" do
    field :status, :string
    field :triggered_at, :utc_datetime_usec
    field :summary, :string
    field :details, :map, default: %{}

    belongs_to :monitor, Monitor

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(execution, attrs) do
    execution
    |> cast(attrs, [:monitor_id, :status, :triggered_at, :summary, :details])
    |> validate_required([:monitor_id, :status, :triggered_at])
    |> update_change(:details, &normalize_details/1)
  end

  defp normalize_details(nil), do: %{}
  defp normalize_details(details) when is_map(details), do: details

  defp normalize_details(details) when is_binary(details) do
    case Jason.decode(details) do
      {:ok, map} when is_map(map) -> map
      _ -> %{"raw" => details}
    end
  end

  defp normalize_details(_), do: %{}
end
