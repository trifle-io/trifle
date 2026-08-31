defmodule Trifle.Observability.Jobs.CleanupTraces do
  @moduledoc "Removes expired Trifle Traces metadata and filesystem payloads."

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 86_400, fields: [:worker]]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Trifle.Observability.cleanup!() do
      {:ok, _deleted} -> :ok
    end
  end
end
