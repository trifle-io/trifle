defmodule Trifle.Chat.SessionStore do
  @moduledoc """
  Persistence layer for ChatLive sessions backed by MongoDB.

  The store keeps a single rolling conversation per user, organization,
  and analytics source combination. Messages are appended in order while
  keeping timestamps for auditing and UI display.
  """

  alias Ecto.UUID
  alias Trifle.Chat.Mongo, as: ChatMongo
  alias Trifle.Chat.Session

  @default_collection "chat_sessions"

  @doc """
  Retrieves the latest session for the given identifiers or creates a new one.
  """
  @spec fetch_or_create(String.t(), String.t(), %{type: String.t(), id: String.t()}) ::
          {:ok, Session.t()} | {:error, term()}
  def fetch_or_create(user_id, organization_id, source_ref) do
    with {:ok, session} <- find_latest(user_id, organization_id, source_ref) do
      {:ok, session}
    else
      {:error, :not_found} ->
        create(user_id, organization_id, source_ref)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Finds the latest session matching the identifiers.
  """
  @spec find_latest(String.t(), String.t(), %{type: String.t(), id: String.t()}) ::
          {:ok, Session.t()} | {:error, term()}
  def find_latest(user_id, organization_id, source_ref) do
    conn = ensure_connection!()

    filter = %{
      "user_id" => user_id,
      "organization_id" => organization_id,
      "source" => %{"type" => source_ref.type, "id" => source_ref.id}
    }

    options = [sort: %{"updated_at" => -1}, limit: 1]

    case Mongo.find(conn, collection(), filter, options) do
      {:error, reason} ->
        {:error, reason}

      cursor ->
        cursor
        |> Enum.to_list()
        |> case do
          [doc] -> {:ok, Session.from_document(doc)}
          [] -> {:error, :not_found}
        end
    end
  rescue
    e -> {:error, e}
  end

  @doc """
  Creates a new blank session for the identifiers.
  """
  @spec create(String.t(), String.t(), %{type: String.t(), id: String.t()}) ::
          {:ok, Session.t()} | {:error, term()}
  def create(user_id, organization_id, source_ref) do
    conn = ensure_connection!()

    timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

    doc = %{
      "_id" => UUID.generate(),
      "user_id" => user_id,
      "organization_id" => organization_id,
      "source" => %{"type" => source_ref.type, "id" => source_ref.id},
      "messages" => [],
      "inserted_at" => timestamp,
      "updated_at" => timestamp,
      "pending_started_at" => nil,
      "progress_events" => []
    }

    case Mongo.insert_one(conn, collection(), doc) do
      {:ok, _} -> {:ok, Session.from_document(doc)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Clears the stored messages for the given session.
  """
  @spec reset(Session.t()) :: {:ok, Session.t()} | {:error, term()}
  def reset(%Session{id: id} = session) do
    conn = ensure_connection!()

    timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

    update = %{
      "$set" => %{
        "messages" => [],
        "updated_at" => timestamp,
        "pending_started_at" => nil,
        "progress_events" => []
      }
    }

    case Mongo.update_one(conn, collection(), %{"_id" => id}, update) do
      {:ok, _} ->
        {:ok,
         %Session{
           session
           | messages: [],
             updated_at: timestamp,
             pending_started_at: nil,
             progress_events: []
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Appends a message to the session, returning the updated session struct.
  """
  @spec append_message(Session.t(), Session.message()) ::
          {:ok, Session.t()} | {:error, term()}
  def append_message(%Session{id: id} = session, message) do
    conn = ensure_connection!()

    normalized =
      message
      |> Map.put_new(:created_at, DateTime.utc_now() |> DateTime.truncate(:second))
      |> Session.normalize_message()

    stored_message = Session.encode_message(normalized)

    timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

    update = %{
      "$push" => %{"messages" => stored_message},
      "$set" => %{"updated_at" => timestamp}
    }

    case Mongo.update_one(conn, collection(), %{"_id" => id}, update) do
      {:ok, _} ->
        {:ok,
         Session.append_message(session, normalized)
         |> Map.put(:updated_at, timestamp)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Appends multiple messages sequentially to minimize round-trips.
  """
  @spec append_messages(Session.t(), [Session.message()]) ::
          {:ok, Session.t()} | {:error, term()}
  def append_messages(session, []), do: {:ok, session}

  def append_messages(%Session{id: id} = session, messages) when is_list(messages) do
    conn = ensure_connection!()

    {normalized_messages, encoded_messages} =
      messages
      |> Enum.map(fn message ->
        normalized =
          message
          |> Map.put_new(:created_at, DateTime.utc_now() |> DateTime.truncate(:second))
          |> Session.normalize_message()

        {normalized, Session.encode_message(normalized)}
      end)
      |> Enum.unzip()

    timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

    update = %{
      "$push" => %{"messages" => %{"$each" => encoded_messages}},
      "$set" => %{"updated_at" => timestamp}
    }

    case Mongo.update_one(conn, collection(), %{"_id" => id}, update) do
      {:ok, _} ->
        updated =
          Enum.reduce(normalized_messages, session, fn message, acc ->
            Session.append_message(acc, message)
          end)
          |> Map.put(:updated_at, timestamp)

        {:ok, updated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Clears any pending marker from the session.
  """
  @spec clear_pending(Session.t()) :: {:ok, Session.t()} | {:error, term()}
  def clear_pending(%Session{id: id} = session) do
    conn = ensure_connection!()

    update = %{"$unset" => %{"pending_started_at" => ""}}

    case Mongo.update_one(conn, collection(), %{"_id" => id}, update) do
      {:ok, _} ->
        {:ok, Session.set_pending_started_at(session, nil)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Resets the progress state for the session (clears events and sets pending start).
  """
  @spec reset_progress(Session.t(), DateTime.t()) :: {:ok, Session.t()} | {:error, term()}
  def reset_progress(%Session{id: id} = session, %DateTime{} = timestamp) do
    conn = ensure_connection!()
    truncated = DateTime.truncate(timestamp, :second)

    update = %{
      "$set" => %{
        "pending_started_at" => truncated,
        "progress_events" => []
      }
    }

    case Mongo.update_one(conn, collection(), %{"_id" => id}, update) do
      {:ok, _} ->
        {:ok,
         session
         |> Session.set_pending_started_at(truncated)
         |> Session.set_progress_events([])}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Replaces the stored progress events for the session.
  """
  @spec set_progress_events(Session.t(), [Session.progress_event()]) ::
          {:ok, Session.t()} | {:error, term()}
  def set_progress_events(%Session{id: id} = session, events) when is_list(events) do
    conn = ensure_connection!()
    encoded = Session.encode_progress_events(events)

    update = %{"$set" => %{"progress_events" => encoded}}

    case Mongo.update_one(conn, collection(), %{"_id" => id}, update) do
      {:ok, _} -> {:ok, Session.set_progress_events(session, events)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Loads a session document by id.
  """
  @spec get(String.t()) :: {:ok, Session.t()} | {:error, term()}
  def get(id) when is_binary(id) do
    conn = ensure_connection!()

    case Mongo.find_one(conn, collection(), %{"_id" => id}) do
      nil -> {:error, :not_found}
      doc -> {:ok, Session.from_document(doc)}
    end
  rescue
    e -> {:error, e}
  end

  defp ensure_connection! do
    unless ChatMongo.enabled?() do
      raise "Chat Mongo connection is not configured. Set config for Trifle.Chat.Mongo."
    end

    conn = ChatMongo.conn_name()

    if Process.whereis(conn) == nil do
      config =
        ChatMongo.config()
        |> Keyword.put_new(:name, conn)

      case Mongo.start_link(config) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
        {:error, reason} -> raise "Failed to start Chat Mongo connection: #{inspect(reason)}"
      end
    end

    conn
  end

  defp collection do
    Application.get_env(:trifle, __MODULE__, [])
    |> Keyword.get(:collection, @default_collection)
  end
end
