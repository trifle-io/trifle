defmodule Trifle.Chat.RunnerRegistryTest do
  use ExUnit.Case, async: false

  alias Trifle.Chat.RunnerRegistry

  test "allows a single owner per session and releases cleanly" do
    session_id = "session-" <> Integer.to_string(System.unique_integer([:positive]))
    owner = self()

    assert :ok == RunnerRegistry.claim(session_id)

    spawn(fn ->
      send(owner, {:claim_result, RunnerRegistry.claim(session_id)})
    end)

    assert_receive {:claim_result, {:error, ^owner}}

    assert :ok == RunnerRegistry.release(session_id)
    assert :ok == RunnerRegistry.claim(session_id)
    assert :ok == RunnerRegistry.release(session_id)
  end
end
