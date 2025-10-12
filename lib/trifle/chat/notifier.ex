defmodule Trifle.Chat.Notifier do
  @moduledoc """
  Lightweight helper for broadcasting chat progress events back to the LiveView.

  The context map may provide either a callback function under `:notify` or a
  target PID. Notifications are best-effort and never raise.
  """

  @type context :: map()
  @type event :: term()

  @spec notify(context(), event()) :: :ok
  def notify(%{notify: fun}, event) when is_function(fun, 1) do
    safe_invoke(fun, event)
  end

  def notify(%{notify: pid}, event) when is_pid(pid) do
    safe_send(pid, event)
  end

  def notify(_, _event), do: :ok

  defp safe_invoke(fun, event) do
    try do
      fun.(event)
      :ok
    rescue
      _ -> :ok
    end
  end

  defp safe_send(pid, event) do
    try do
      send(pid, event)
      :ok
    rescue
      _ -> :ok
    end
  end
end
