defmodule Trifle.Chat.Session do
  @moduledoc """
  In-memory representation of a ChatLive conversation persisted to MongoDB.

  A session belongs to a specific user within an organization and analytics
  source. The message list mirrors the OpenAI chat API payload while adding
  timestamps for local use.
  """

  alias Ecto.UUID
  alias Trifle.Chat.Progress
  @enforce_keys [:id, :user_id, :organization_id, :source, :messages]
  defstruct [
    :id,
    :user_id,
    :organization_id,
    :source,
    :messages,
    :inserted_at,
    :updated_at,
    :pending_started_at,
    progress_events: []
  ]

  @bson_datetime Module.concat(BSON, DateTime)

  @type message_role :: String.t()

  @type tool_call :: %{
          id: String.t(),
          type: String.t(),
          function: %{
            name: String.t(),
            arguments: String.t()
          }
        }

  @type message :: %{
          required(:role) => message_role(),
          optional(:content) => String.t() | nil,
          optional(:created_at) => DateTime.t(),
          optional(:tool_calls) => [tool_call()],
          optional(:tool_call_id) => String.t(),
          optional(:name) => String.t()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          user_id: String.t(),
          organization_id: String.t(),
          source: %{type: String.t(), id: String.t()},
          messages: [message()],
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          progress_events: [progress_event()]
        }

  @type progress_event :: %{
          required(:id) => String.t(),
          required(:type) => String.t(),
          optional(:payload) => map(),
          optional(:text) => String.t(),
          optional(:started_at) => DateTime.t() | nil,
          optional(:finished_at) => DateTime.t() | nil,
          optional(:display) => boolean()
        }

  @doc """
  Builds a session struct from a MongoDB document.
  """
  @spec from_document(map()) :: t()
  def from_document(%{} = doc) do
    %__MODULE__{
      id: to_string(Map.fetch!(doc, "_id")),
      user_id: doc |> Map.get("user_id") |> to_string(),
      organization_id: doc |> Map.get("organization_id") |> to_string(),
      source: normalize_source(doc["source"]),
      messages: normalize_messages(doc["messages"] || []),
      inserted_at: normalize_datetime(doc["inserted_at"]),
      updated_at: normalize_datetime(doc["updated_at"]),
      pending_started_at: normalize_datetime(doc["pending_started_at"]),
      progress_events: normalize_progress_events(doc["progress_events"])
    }
  end

  @doc """
  Converts a session struct back into a MongoDB document map.
  """
  @spec to_document(t()) :: map()
  def to_document(%__MODULE__{} = session) do
    %{
      "_id" => session.id,
      "user_id" => session.user_id,
      "organization_id" => session.organization_id,
      "source" => session.source,
      "messages" => Enum.map(session.messages, &encode_message/1),
      "inserted_at" => encode_datetime(session.inserted_at),
      "updated_at" => encode_datetime(session.updated_at),
      "pending_started_at" => encode_datetime(session.pending_started_at),
      "progress_events" => encode_progress_events(session.progress_events)
    }
  end

  @doc """
  Returns a new session struct with an appended message.
  """
  @spec append_message(t(), message()) :: t()
  def append_message(%__MODULE__{} = session, %{} = message) do
    normalized_message =
      message
      |> Map.put_new(:created_at, DateTime.utc_now() |> DateTime.truncate(:second))
      |> normalize_message()

    %__MODULE__{
      session
      | messages: session.messages ++ [normalized_message],
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  @doc """
  Replaces the session messages with the provided list.
  """
  @spec replace_messages(t(), [message()]) :: t()
  def replace_messages(%__MODULE__{} = session, messages) when is_list(messages) do
    normalized =
      messages
      |> Enum.map(&normalize_message/1)

    %__MODULE__{
      session
      | messages: normalized,
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  defp normalize_source(%{"type" => type, "id" => id}) when is_binary(type) and is_binary(id) do
    %{"type" => type, "id" => id}
  end

  defp normalize_source(_), do: %{"type" => "unknown", "id" => "unknown"}

  defp normalize_messages(messages) do
    Enum.map(messages, &normalize_message/1)
  end

  @doc """
  Normalizes a single message map into the internal representation.
  """
  @spec normalize_message(map()) :: message()
  def normalize_message(%{} = message) do
    %{
      role: Map.get(message, :role) || Map.get(message, "role"),
      content: Map.get(message, :content, Map.get(message, "content")),
      created_at:
        message
        |> Map.get(:created_at, Map.get(message, "created_at"))
        |> normalize_datetime(),
      tool_calls: normalize_tool_calls(message),
      tool_call_id: Map.get(message, :tool_call_id, Map.get(message, "tool_call_id")),
      name: Map.get(message, :name, Map.get(message, "name"))
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp normalize_tool_calls(message) do
    tool_calls =
      message
      |> Map.get(:tool_calls, Map.get(message, "tool_calls"))
      |> Kernel.||([])

    Enum.map(tool_calls, fn call ->
      %{
        id: Map.get(call, :id, Map.get(call, "id")),
        type: Map.get(call, :type, Map.get(call, "type")),
        function:
          call
          |> Map.get(:function, Map.get(call, "function", %{}))
          |> normalize_function()
      }
    end)
    |> case do
      [] -> nil
      list -> list
    end
  end

  defp normalize_function(%{} = function) do
    %{
      name: Map.get(function, :name, Map.get(function, "name")),
      arguments: Map.get(function, :arguments, Map.get(function, "arguments", "{}"))
    }
  end

  defp normalize_datetime(nil), do: nil
  defp normalize_datetime(%DateTime{} = dt), do: dt

  defp normalize_datetime(%struct{utc: millis}) when struct == @bson_datetime do
    millis
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.truncate(:second)
  end

  defp normalize_datetime(%{"$date" => value}) do
    DateTime.from_iso8601(value)
    |> case do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp normalize_datetime(value) when is_integer(value) do
    value
    |> DateTime.from_unix!(:second)
    |> DateTime.truncate(:second)
  end

  defp normalize_datetime(_), do: nil

  @doc """
  Updates the pending_started_at timestamp on the session.
  """
  @spec set_pending_started_at(t(), DateTime.t() | nil) :: t()
  def set_pending_started_at(%__MODULE__{} = session, nil) do
    %__MODULE__{session | pending_started_at: nil}
  end

  def set_pending_started_at(%__MODULE__{} = session, %DateTime{} = dt) do
    %__MODULE__{session | pending_started_at: DateTime.truncate(dt, :second)}
  end

  @doc """
  Replaces the progress events on the session.
  """
  @spec set_progress_events(t(), [progress_event()]) :: t()
  def set_progress_events(%__MODULE__{} = session, events) when is_list(events) do
    %__MODULE__{session | progress_events: normalize_progress_events(events)}
  end

  @doc """
  Appends a progress event and finishes the previous one if needed.
  """
  @spec append_progress_event(t(), String.t(), map(), DateTime.t()) :: t()
  def append_progress_event(%__MODULE__{} = session, type, payload, %DateTime{} = timestamp) do
    truncated = DateTime.truncate(timestamp, :second)
    text = Progress.text(type, payload)

    normalized_type = type |> to_string()
    normalized_payload = payload || %{}

    {events, _} =
      session.progress_events
      |> Enum.reduce({[], true}, fn event, {acc, first?} ->
        if first? do
          {[finish_event(event, truncated) | acc], false}
        else
          {[event | acc], false}
        end
      end)

    new_event = %{
      id: UUID.generate(),
      type: normalized_type,
      payload: normalized_payload,
      text: text,
      started_at: truncated,
      finished_at: nil,
      display: true
    }

    %__MODULE__{session | progress_events: Enum.reverse([new_event | events])}
  end

  @doc """
  Marks the active progress event as finished.
  """
  @spec finish_active_progress_event(t(), DateTime.t()) :: t()
  def finish_active_progress_event(%__MODULE__{} = session, %DateTime{} = timestamp) do
    truncated = DateTime.truncate(timestamp, :second)

    progress_events =
      session.progress_events
      |> Enum.reverse()
      |> case do
        [current | rest] ->
          Enum.reverse([finish_event(current, truncated) | rest])

        other ->
          other
      end

    %__MODULE__{session | progress_events: progress_events}
  end

  @doc """
  Encodes a normalized message for MongoDB storage.
  """
  @spec encode_message(message()) :: map()
  def encode_message(%{} = message) do
    %{
      "role" => Map.get(message, :role),
      "content" => Map.get(message, :content),
      "created_at" => encode_datetime(Map.get(message, :created_at)),
      "tool_calls" => encode_tool_calls(Map.get(message, :tool_calls)),
      "tool_call_id" => Map.get(message, :tool_call_id),
      "name" => Map.get(message, :name)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp encode_tool_calls(nil), do: nil

  defp encode_tool_calls(tool_calls) when is_list(tool_calls) do
    Enum.map(tool_calls, fn call ->
      %{
        "id" => Map.get(call, :id),
        "type" => Map.get(call, :type),
        "function" =>
          call
          |> Map.get(:function, %{})
          |> then(fn function ->
            %{
              "name" => Map.get(function, :name),
              "arguments" => Map.get(function, :arguments)
            }
            |> Enum.reject(fn {_k, v} -> is_nil(v) end)
            |> Map.new()
          end)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    end)
  end

  defp encode_datetime(nil), do: nil
  defp encode_datetime(%DateTime{} = dt), do: DateTime.truncate(dt, :second)
  defp encode_datetime(%struct{} = dt) when struct == @bson_datetime, do: dt

  defp encode_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp encode_datetime(value) when is_integer(value), do: value
  defp encode_datetime(_), do: nil

  defp normalize_progress_events(nil), do: []

  defp normalize_progress_events(events) when is_list(events) do
    Enum.map(events, fn event ->
      type_value = Map.get(event, "type") || Map.get(event, :type)

      normalized_type =
        cond do
          is_atom(type_value) -> Atom.to_string(type_value)
          is_binary(type_value) -> type_value
          true -> "unknown"
        end

      %{
        id: Map.get(event, "id") || Map.get(event, :id) || UUID.generate(),
        type: normalized_type,
        payload: Map.get(event, "payload") || Map.get(event, :payload) || %{},
        text: Map.get(event, "text") || Map.get(event, :text),
        started_at:
          normalize_datetime(Map.get(event, "started_at") || Map.get(event, :started_at)),
        finished_at:
          normalize_datetime(Map.get(event, "finished_at") || Map.get(event, :finished_at)),
        display: Map.get(event, "display") || Map.get(event, :display) || true
      }
    end)
  end

  defp normalize_progress_events(_), do: []

  def encode_progress_events(events) when is_list(events) do
    Enum.map(events, fn event ->
      %{
        "id" => Map.get(event, :id),
        "type" => Map.get(event, :type),
        "payload" => Map.get(event, :payload) || %{},
        "text" => Map.get(event, :text),
        "started_at" => encode_datetime(Map.get(event, :started_at)),
        "finished_at" => encode_datetime(Map.get(event, :finished_at)),
        "display" => Map.get(event, :display, true)
      }
    end)
  end

  def encode_progress_events(_), do: []

  defp finish_event(%{finished_at: nil} = event, %DateTime{} = timestamp) do
    Map.put(event, :finished_at, timestamp)
  end

  defp finish_event(event, _timestamp), do: event
end
