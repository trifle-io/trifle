defmodule Trifle.Chat.RunnerRegistry do
  @moduledoc """
  Tracks which LiveView currently owns an in-flight chat run for a session.

  Only one process may actively drive the OpenAI loop for a given chat session
  at a time. Other tabs may still observe the persisted session updates.
  """

  @registry __MODULE__

  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: @registry)
  end

  @spec claim(String.t()) :: :ok | {:error, pid()}
  def claim(session_id) when is_binary(session_id) do
    case Registry.register(@registry, session_id, nil) do
      {:ok, _} ->
        :ok

      {:error, {:already_registered, pid}} ->
        {:error, pid}
    end
  end

  @spec release(String.t()) :: :ok
  def release(session_id) when is_binary(session_id) do
    case Registry.lookup(@registry, session_id) do
      [{pid, _}] when pid == self() ->
        Registry.unregister(@registry, session_id)
        :ok

      _ ->
        :ok
    end
  end
end
