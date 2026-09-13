defmodule Trifle.Traces.ActivityFetchTest do
  use Trifle.DataCase
  import Trifle.OrganizationsFixtures
  import Trifle.BillingFixtures
  alias Trifle.Traces.Activity

  setup do
    org = organization_fixture()
    app_entitlement_fixture(org)

    database =
      database_fixture(%{
        organization: org,
        driver: "postgres",
        host: "postgres",
        port: 5432,
        database_name: "test",
        username: "test",
        password: "test",
        trace_config: %{
          "index_name" => "trace_activity_test",
          "data_driver" => "file",
          "data_path" => "/tmp/traces",
          "retention_days" => 7,
          "gzip" => false
        }
      })

    %{membership: %{organization_id: org.id}, database: database}
  end

  test "discovers literal keys and reads state metrics with bounded concurrency, not transponders",
       context do
    parent = self()
    at = ~U[2026-09-01 00:00:00Z]
    keys = ["jobs/App.Worker", "jobs/*", "jobs/test%2Erb", "jobs/東京.rb", "jobs/test.rb"]
    counter = start_supervised!({Agent, fn -> %{active: 0, peak: 0} end})

    fetcher = fn source, key, from, to, granularity, opts ->
      send(parent, {:fetch, source.record.id, key, from, to, granularity, opts})

      series =
        if key == "__system__key__" do
          %{at: [at], values: [%{"keys" => Map.new(keys, &{&1, 1})}]}
        else
          Agent.update(counter, fn c ->
            %{active: c.active + 1, peak: max(c.peak, c.active + 1)}
          end)

          Process.sleep(10)
          Agent.update(counter, &%{&1 | active: &1.active - 1})
          %{at: [at], values: [%{"count" => 1, "states" => %{"warning" => 1}}]}
        end

      {:ok, %{series: Trifle.Stats.series(series)}}
    end

    to = DateTime.add(at, 1, :hour)

    assert {:ok, input} =
             Activity.fetch(context.membership, context.database.id, at, to, "1h",
               fetch_series: fetcher
             )

    assert Enum.sort(Map.keys(input.metrics)) == Enum.sort(keys)
    assert Activity.build(input, "jobs", "warning").total == 5
    assert Agent.get(counter, & &1.peak) <= 4

    for key <- ["__system__key__" | keys] do
      assert_receive {:fetch, id, ^key, ^at, ^to, "1h", opts}
      assert id == context.database.id
      assert opts[:transponders] == :none
      assert opts[:progressive_concurrency] == 1
    end
  end

  test "a failed metric read cannot masquerade as a partial complete activity chart", context do
    at = ~U[2026-09-01 00:00:00Z]

    for failure <- [:error, :raise] do
      fetcher = fn _, key, _, _, _, _ ->
        cond do
          key == "__system__key__" ->
            {:ok, %{series: %{at: [at], values: [%{"keys" => %{"jobs/a" => 1}}]}}}

          failure == :raise ->
            raise "storage unavailable"

          true ->
            {:error, :unavailable}
        end
      end

      assert {:error, :storage_unavailable} =
               Activity.fetch(context.membership, context.database.id, at, at, "1h",
                 fetch_series: fetcher
               )
    end
  end

  test "an inaccessible source never calls the Stats reader", context do
    fetcher = fn _, _, _, _, _, _ -> flunk("must authorize before reading") end

    assert {:error, _} =
             Activity.fetch(context.membership, Ecto.UUID.generate(), nil, nil, "1h",
               fetch_series: fetcher
             )
  end
end
