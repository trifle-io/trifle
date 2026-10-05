defmodule Trifle.Observability.TraceMetricsTest do
  use ExUnit.Case, async: false

  alias Trifle.{Stats, Traces}
  alias Trifle.Stats.Driver.Sqlite
  alias Trifle.Traces.Configuration

  @worker "Trifle.Monitors.Jobs.DispatchRunner"
  @metric_key "jobs/#{@worker}"

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

  for state <- [:success, :warning, :error], mode <- [:live, :deferred] do
    test "Oban #{mode} #{state} wrapup records native activity metrics", %{
      stats_config: stats_config
    } do
      state = unquote(state)
      mode = unquote(mode)
      parent = self()

      config =
        Configuration.new(
          index_driver: Traces.Driver.Index.Memory.new(),
          data_driver: Traces.Driver.Data.Memory.new(),
          stats_config: stats_config,
          default_mode: mode,
          bump_every: 0
        )
        |> Configuration.add_callback(:wrapup, &send(parent, {:wrapped, &1}))

      args = %{"monitor_id" => "monitor-42", "options" => %{"values" => [false, nil, 0]}}
      job = %Oban.Job{id: 42, worker: @worker, queue: "default", attempt: 1, args: args}
      options = [config: config]
      from = DateTime.utc_now()

      Traces.Oban.handle_event([:oban, :job, :start], %{}, %{job: job}, options)
      Traces.trace("Executing the job")

      assert %{values: []} =
               Stats.values(@metric_key, from, DateTime.utc_now(), "1h", stats_config,
                 skip_blanks: true
               )

      finish_job(state, job, options)

      assert_receive {:wrapped, tracer}
      assert tracer.key == "jobs/#{@worker}"
      assert tracer.state == state
      assert tracer.mode == mode
      assert tracer.meta == args
      record = Traces.Tracer.trace_record(tracer)
      assert record.length == length(Traces.payload(record, config: config))
      assert record.length > 0
      assert Traces.find(tracer.reference, config: config).meta == args

      assert Traces.find(tracer.reference, config: config).context == %{
               id: 42,
               attempt: 1,
               queue: "default",
               worker: @worker
             }

      assert Traces.current_tracer() == nil
      to = DateTime.utc_now()

      assert %{values: [values]} =
               Stats.values(@metric_key, from, to, "1h", stats_config, skip_blanks: true)

      assert Map.drop(values, ["duration"]) == %{
               "count" => 1,
               "states" => %{to_string(state) => 1},
               "entries" => %{"count" => record.length}
             }

      assert %{"count" => 1, "sum" => duration, "square" => square, "states" => states} =
               values["duration"]

      assert duration >= 0
      assert duration == record.duration
      assert square == duration * duration

      assert states == %{
               to_string(state) => %{"count" => 1, "sum" => duration, "square" => square}
             }

      assert %{values: [system]} =
               Stats.values("__system__key__", from, to, "1h", stats_config, skip_blanks: true)

      assert system["keys"] == %{@metric_key => 1}
    end
  end

  test "records native durations and counts across live bumps and deferred wrapup", %{
    stats_config: stats_config
  } do
    from = DateTime.utc_now()

    records =
      for mode <- [:live, :deferred] do
        config =
          Configuration.new(
            index_driver: Traces.Driver.Index.Memory.new(),
            data_driver: Traces.Driver.Data.Memory.new(),
            stats_config: stats_config,
            bump_every: 0
          )

        {:ok, tracer} = Traces.start_tracer(@metric_key, config: config, mode: mode)
        Traces.trace("first step", tracer: tracer)
        Process.sleep(5)
        Traces.trace("second step", tracer: tracer)
        final = Traces.wrapup(tracer: tracer)
        record = Traces.Tracer.trace_record(final)
        assert record.duration >= 5
        assert record.length == 3
        record
      end

    assert %{values: [values]} =
             Stats.values(@metric_key, from, DateTime.utc_now(), "1h", stats_config,
               skip_blanks: true
             )

    assert values["count"] == 2
    assert values["entries"]["count"] == 6
    assert values["duration"]["count"] == 2
    assert values["duration"]["sum"] == Enum.sum(Enum.map(records, & &1.duration))

    assert values["duration"]["square"] ==
             Enum.sum(Enum.map(records, &(&1.duration * &1.duration)))

    assert Map.keys(values["duration"]["states"]) == ["success"]
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
