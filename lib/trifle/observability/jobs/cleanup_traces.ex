defmodule Trifle.Observability.Jobs.CleanupTraces do
  @moduledoc "Removes expired Trifle Traces metadata and managed payloads."

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 86_400, fields: [:worker]]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Trifle.Traces.trace("Clean up expired traces", head: true)

    case Trifle.Observability.cleanup!() do
      {:ok, deleted} ->
        Trifle.Traces.trace("Expired trace indexes deleted: #{deleted}")
        :ok
    end
  end
end
