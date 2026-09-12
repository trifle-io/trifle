defmodule Trifle.Observability.TraceMetricsTest do
  use ExUnit.Case, async: false

  alias Trifle.{Observability, Stats, Traces}
  alias Trifle.Stats.Driver.Sqlite
  alias Trifle.Traces.Configuration

  @worker "Trifle.Monitors.Jobs.DispatchRunner"
  @metric_key "jobs::#{@worker}"

  setup do
    previous = Application.fetch_env(:trifle_stats, :global_config)

    on_exit(fn ->
      case previous do
        {:ok, config} -> Application.put_env(:trifle_stats, :global_config, config)
        :error -> Application.delete_env(:trifle_stats, :global_config)
      end
    end)

    conn = start_supervised!({Exqlite, database: ":memory:"})
    :ok = Sqlite.setup!(conn, "trace_metrics")

    config =
      Stats.configure(
        driver: Sqlite.new(conn, "trace_metrics"),
        time_zone: "Etc/UTC",
        track_granularities: ["1h"],
        buffer_enabled: false
      )

    %{stats_config: config}
  end

  for state <- [:success, :warning, :error] do
    test "Oban #{state} wrapup records a short job key without changing values", %{
      stats_config: stats_config
    } do
      state = unquote(state)
      parent = self()

      config =
        Configuration.new(on_wrapup: &Observability.record_trace/1)
        |> Configuration.add_callback(:wrapup, &send(parent, {:wrapped, &1}))

      job = %Oban.Job{id: 42, worker: @worker, queue: "default", attempt: 1, args: %{}}
      options = [config: config, meta: &Observability.oban_meta/1]
      from = DateTime.utc_now()

      Traces.Oban.handle_event([:oban, :job, :start], %{}, %{job: job}, options)
      Traces.trace("Executing the job")

      finish_job(state, job, options)

      assert_receive {:wrapped, tracer}
      assert tracer.key == "jobs/#{@worker}"
      assert tracer.state == state
      assert Traces.current_tracer() == nil
      to = DateTime.utc_now()

      assert %{values: [values]} =
               Stats.values(@metric_key, from, to, "1h", stats_config, skip_blanks: true)

      assert values == %{
               "count" => 1,
               "states" => %{to_string(state) => 1},
               "entries" => %{"count" => length(tracer.data)}
             }

      assert %{values: [system]} =
               Stats.values("__system__key__", from, to, "1h", stats_config, skip_blanks: true)

      assert system["keys"] == %{@metric_key => 1}
    end
  end

  defp finish_job(:error, job, options) do
    Traces.Oban.handle_event(
      [:oban, :job, :exception],
      %{},
      %{job: job, reason: RuntimeError.exception("job failed")},
      options
    )
  end

  defp finish_job(state, job, options) do
    if state == :warning, do: Traces.warn()

    Traces.Oban.handle_event(
      [:oban, :job, :stop],
      %{},
      %{job: job, state: :success},
      options
    )
  end
end
