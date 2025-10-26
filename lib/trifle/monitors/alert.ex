defmodule Trifle.Monitors.Alert do
  @moduledoc """
  Represents a single alert definition attached to a monitor.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Trifle.Monitors.Monitor

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @strategy_values [:threshold, :range, :anomaly_detection]

  schema "monitor_alerts" do
    field :analysis_strategy, Ecto.Enum,
      values: @strategy_values,
      default: :threshold

    belongs_to :monitor, Monitor

    timestamps()
  end

  @doc false
  def changeset(alert, attrs) do
    alert
    |> cast(attrs, [:analysis_strategy, :monitor_id])
    |> validate_required([:analysis_strategy, :monitor_id])
  end
end
