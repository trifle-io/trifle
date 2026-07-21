defmodule Trifle.SystemNotifications do
  @moduledoc """
  Queues internal system event emails for all system administrators.

  Product operations never depend on email availability: failures to enqueue are
  logged and returned to the caller, which may safely ignore them.
  """

  require Logger

  alias Trifle.SystemNotifications.Jobs.Dispatch

  @events ~w(
    user_created
    user_invited
    project_created
    database_created
    database_checked
    subscription_created
    subscription_cancellation_scheduled
    subscription_cancelled
  )

  @spec enqueue(atom() | String.t(), map()) :: :ok | {:error, term()}
  def enqueue(event, payload), do: enqueue(event, payload, [])

  @spec enqueue(atom() | String.t(), map(), keyword()) :: :ok | {:error, term()}
  def enqueue(event, payload, opts) when is_map(payload) and is_list(opts) do
    event = to_string(event)

    if event in @events do
      notification_id = Keyword.get(opts, :idempotency_key, Ecto.UUID.generate())

      args = %{
        "notification_id" => notification_id,
        "event" => event,
        "payload" => stringify_keys(payload)
      }

      case Oban.insert(Dispatch.new(args)) do
        {:ok, _job} ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to enqueue system notification #{event}: #{inspect(reason)}")

          {:error, reason}
      end
    else
      {:error, :unsupported_event}
    end
  rescue
    error ->
      Logger.warning(
        "Failed to enqueue system notification #{event}: #{Exception.message(error)}"
      )

      {:error, error}
  end

  def enqueue(_event, _payload, _opts), do: {:error, :invalid_payload}

  defp stringify_keys(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp stringify_keys(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(nil), do: nil
  defp stringify_keys(value) when is_boolean(value), do: value
  defp stringify_keys(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_keys(value), do: value
end
