defmodule Trifle.Chat.SessionStore do
  @moduledoc """
  Persistence layer for ChatLive sessions backed by Postgres.

  The store keeps a single rolling conversation per user, organization,
  and analytics source combination. Messages are appended in order while
  keeping timestamps for auditing and UI display.
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Changeset
  alias Ecto.UUID
  alias Trifle.Chat.Session
  alias Trifle.Chat.SessionRecord
  alias Trifle.Repo

  @identity_index "chat_sessions_identity_index"

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
  def find_latest(user_id, organization_id, %{type: type, id: source_id}) do
    query =
      from session in SessionRecord,
        where:
          session.user_id == ^cast_uuid!(user_id) and
            session.organization_id == ^cast_uuid!(organization_id) and
            session.source_type == ^to_string(type) and
            session.source_id == ^cast_uuid!(source_id),
        order_by: [desc: session.updated_at],
        limit: 1

    case Repo.one(query) do
      nil -> {:error, :not_found}
      record -> {:ok, Session.from_record(record)}
    end
  rescue
    e -> {:error, e}
  end

  @doc """
  Creates a new blank session for the identifiers.
  """
  @spec create(String.t(), String.t(), %{type: String.t(), id: String.t()}) ::
          {:ok, Session.t()} | {:error, term()}
  def create(user_id, organization_id, %{type: type, id: source_id}) do
    attrs = %{
      user_id: cast_uuid!(user_id),
      organization_id: cast_uuid!(organization_id),
      source_type: to_string(type),
      source_id: cast_uuid!(source_id),
      messages: [],
      progress_events: [],
      pending_started_at: nil
    }

    %SessionRecord{}
    |> SessionRecord.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, record} ->
        {:ok, Session.from_record(record)}

      {:error, %Changeset{} = changeset} ->
        if unique_conflict?(changeset) do
          find_latest(user_id, organization_id, %{type: to_string(type), id: source_id})
        else
          {:error, changeset}
        end
    end
  rescue
    e -> {:error, e}
  end

  @doc """
  Clears the stored messages for the given session.
  """
  @spec reset(Session.t()) :: {:ok, Session.t()} | {:error, term()}
  def reset(%Session{id: id}) do
    transaction(id, fn record, session ->
      updated =
        session
        |> Session.replace_messages([])
        |> Session.set_pending_started_at(nil)
        |> Session.set_progress_events([])

      persist_session(record, updated)
    end)
  end

  @doc """
  Restores the persisted session to match the provided snapshot.
  """
  @spec restore(Session.t(), Session.t()) :: {:ok, Session.t()} | {:error, term()}
  def restore(%Session{id: id}, %Session{id: id} = snapshot) do
    transaction(id, fn record, _current ->
      persist_session(record, snapshot)
    end)
  end

  def restore(_current, _snapshot), do: {:error, :mismatched_session}

  @doc """
  Appends a message to the session, returning the updated session struct.
  """
  @spec append_message(Session.t(), Session.message()) ::
          {:ok, Session.t()} | {:error, term()}
  def append_message(%Session{id: id}, message) do
    transaction(id, fn record, session ->
      session
      |> Session.append_message(message)
      |> then(&persist_session(record, &1))
    end)
  end

  @doc """
  Appends multiple messages sequentially to minimize round-trips.
  """
  @spec append_messages(Session.t(), [Session.message()]) ::
          {:ok, Session.t()} | {:error, term()}
  def append_messages(session, []), do: {:ok, session}

  def append_messages(%Session{id: id}, messages) when is_list(messages) do
    transaction(id, fn record, session ->
      updated =
        Enum.reduce(messages, session, fn message, acc ->
          Session.append_message(acc, message)
        end)

      persist_session(record, updated)
    end)
  end

  @doc """
  Clears any pending marker from the session.
  """
  @spec clear_pending(Session.t()) :: {:ok, Session.t()} | {:error, term()}
  def clear_pending(%Session{id: id}) do
    transaction(id, fn record, session ->
      session
      |> Session.set_pending_started_at(nil)
      |> then(&persist_session(record, &1))
    end)
  end

  @doc """
  Resets the progress state for the session (clears events and sets pending start).
  """
  @spec reset_progress(Session.t(), DateTime.t()) :: {:ok, Session.t()} | {:error, term()}
  def reset_progress(%Session{id: id}, %DateTime{} = timestamp) do
    truncated = DateTime.truncate(timestamp, :second)

    transaction(id, fn record, session ->
      session
      |> Session.set_pending_started_at(truncated)
      |> Session.set_progress_events([])
      |> then(&persist_session(record, &1))
    end)
  end

  @doc """
  Replaces the stored progress events for the session.
  """
  @spec set_progress_events(Session.t(), [Session.progress_event()]) ::
          {:ok, Session.t()} | {:error, term()}
  def set_progress_events(%Session{id: id}, events) when is_list(events) do
    transaction(id, fn record, session ->
      session
      |> Session.set_progress_events(events)
      |> then(&persist_session(record, &1))
    end)
  end

  @doc """
  Loads a session by id.
  """
  @spec get(String.t()) :: {:ok, Session.t()} | {:error, term()}
  def get(id) when is_binary(id) do
    case Repo.get(SessionRecord, cast_uuid!(id)) do
      nil -> {:error, :not_found}
      record -> {:ok, Session.from_record(record)}
    end
  rescue
    e -> {:error, e}
  end

  defp transaction(id, fun) do
    Repo.transaction(fn ->
      case lock_session(id) do
        nil ->
          Repo.rollback(:not_found)

        record ->
          session = Session.from_record(record)

          case fun.(record, session) do
            {:ok, updated_session} ->
              updated_session

            {:error, reason} ->
              Repo.rollback(reason)
          end
      end
    end)
    |> unwrap_transaction()
  end

  defp lock_session(id) do
    query =
      from session in SessionRecord,
        where: session.id == ^cast_uuid!(id),
        lock: "FOR UPDATE"

    Repo.one(query)
  end

  defp persist_session(record, %Session{} = session) do
    attrs =
      session
      |> Session.to_record_attrs()
      |> normalize_persistence_attrs()

    record
    |> SessionRecord.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_record} -> {:ok, Session.from_record(updated_record)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_persistence_attrs(attrs) do
    attrs
    |> Map.update!(:user_id, &cast_uuid!/1)
    |> Map.update!(:organization_id, &cast_uuid!/1)
    |> Map.update!(:source_id, &cast_uuid!/1)
  end

  defp unwrap_transaction({:ok, value}), do: {:ok, value}
  defp unwrap_transaction({:error, %Changeset{} = changeset}), do: {:error, changeset}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}

  defp cast_uuid!(value) when is_binary(value) do
    case UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> raise ArgumentError, "expected binary UUID, got: #{inspect(value)}"
    end
  end

  defp cast_uuid!(value) when is_nil(value) do
    raise ArgumentError, "expected UUID, got nil"
  end

  defp cast_uuid!(value), do: value

  defp unique_conflict?(%Changeset{constraints: constraints}) do
    Enum.any?(constraints, fn
      %{constraint_type: :unique, name: @identity_index} -> true
      _ -> false
    end)
  end
end
