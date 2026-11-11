defmodule TrifleApp.Exporters.ChromeLimiterTest do
  use ExUnit.Case, async: true

  alias TrifleApp.Exporters.ChromeLimiter

  setup do
    name = :"chrome_limiter_#{System.unique_integer([:positive])}"
    start_supervised!({ChromeLimiter, name: name, max_concurrency: 2})
    {:ok, server: name}
  end

  defp hold(server, parent, label) do
    spawn(fn ->
      ChromeLimiter.run(
        fn ->
          send(parent, {:started, label, self()})

          receive do
            :finish -> :ok
          end
        end,
        server: server,
        wait_timeout_ms: 5_000
      )

      send(parent, {:finished, label})
    end)
  end

  test "returns the function's result", %{server: server} do
    assert ChromeLimiter.run(fn -> {:ok, 42} end, server: server) == {:ok, 42}
  end

  test "never runs more than max_concurrency at once and queues the rest in order", %{
    server: server
  } do
    parent = self()
    hold(server, parent, :a)
    hold(server, parent, :b)
    assert_receive {:started, :a, pid_a}
    assert_receive {:started, :b, _pid_b}

    hold(server, parent, :c)
    refute_receive {:started, :c, _}, 100

    send(pid_a, :finish)
    assert_receive {:finished, :a}
    assert_receive {:started, :c, _pid_c}
  end

  test "gives up with :export_busy when no slot frees up in time", %{server: server} do
    parent = self()
    hold(server, parent, :a)
    hold(server, parent, :b)
    assert_receive {:started, :a, _}
    assert_receive {:started, :b, pid_b}

    assert ChromeLimiter.run(fn -> :ran end, server: server, wait_timeout_ms: 50) ==
             {:error, :export_busy}

    # The timed-out caller must not occupy a slot later.
    send(pid_b, :finish)
    assert_receive {:finished, :b}
    assert ChromeLimiter.run(fn -> :ran end, server: server, wait_timeout_ms: 500) == :ran
  end

  test "releases the slot when the function raises or the caller dies", %{server: server} do
    parent = self()

    assert_raise RuntimeError, fn ->
      ChromeLimiter.run(fn -> raise "boom" end, server: server)
    end

    holder = hold(server, parent, :a)
    hold(server, parent, :b)
    assert_receive {:started, :a, _}
    assert_receive {:started, :b, _}

    Process.exit(holder, :kill)

    assert ChromeLimiter.run(fn -> :ran end, server: server, wait_timeout_ms: 1_000) == :ran
  end

  test "runs unthrottled when the limiter is not started" do
    assert ChromeLimiter.run(fn -> :ran end, server: :no_such_limiter) == :ran
  end
end
