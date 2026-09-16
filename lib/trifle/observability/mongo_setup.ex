defmodule Trifle.Observability.MongoSetup do
  @moduledoc false

  use GenServer
  require Logger

  @retry_ms 30_000

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @impl true
  def init(options) do
    send(self(), :setup)
    {:ok, options}
  end

  @impl true
  def handle_info(:setup, options) do
    connection = Keyword.fetch!(options, :connection)

    try do
      :ok =
        Trifle.Stats.Driver.Mongo.setup!(
          connection,
          Keyword.fetch!(options, :stats_collection)
        )

      :ok =
        Trifle.Traces.Driver.Index.Mongo.setup!(
          connection,
          collection_name: Keyword.fetch!(options, :traces_collection)
        )

      {:noreply, options}
    rescue
      error ->
        Logger.warning(
          "Internal MongoDB observability setup failed: #{inspect(error.__struct__)}"
        )

        Process.send_after(self(), :setup, @retry_ms)
        {:noreply, options}
    catch
      kind, _reason ->
        Logger.warning("Internal MongoDB observability setup failed: #{kind}")
        Process.send_after(self(), :setup, @retry_ms)
        {:noreply, options}
    end
  end
end
