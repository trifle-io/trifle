defmodule TrifleApp.Exports.LayoutStore do
  @moduledoc """
  Temporary storage for export layouts during headless rendering.

  Layouts are cached in ETS for fast local access and mirrored in Postgres so
  that other nodes in the cluster can retrieve them when load-balancing sends
  the export request elsewhere.
  """

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Trifle.Repo
  alias TrifleApp.Exports.{Layout, LayoutSessionRecord}

  @table :trifle_export_layouts
  @ttl_ms 60_000

  @type layout_id :: String.t()

  @doc """
  Stores the given layout for a limited time and returns its storage ID.
  """
  @spec put(Layout.t(), Keyword.t()) :: layout_id()
  def put(%Layout{} = layout, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, @ttl_ms)
    id = generate_id()
    expires_at_ms = System.system_time(:millisecond) + ttl

    :ets.insert(table(), {id, layout, expires_at_ms})
    persist_layout(id, layout, expires_at_ms)
    id
  end

  @doc """
  Retrieves a layout by ID without removing it.
  """
  @spec fetch(layout_id()) :: {:ok, Layout.t()} | {:error, :not_found | :expired}
  def fetch(id) when is_binary(id) do
    case local_fetch(id) do
      {:ok, _layout} = ok ->
        ok

      {:error, :expired} = expired ->
        expired

      {:error, :not_found} ->
        db_fetch(id)
    end
  end

  @doc """
  Retrieves and deletes the layout if it is still valid.
  """
  @spec take(layout_id()) :: {:ok, Layout.t()} | {:error, :not_found | :expired}
  def take(id) when is_binary(id) do
    case local_take(id) do
      {:ok, _layout} = ok ->
        _ = delete_from_db(id)
        ok

      {:error, :expired} = expired ->
        _ = delete_from_db(id)
        expired

      {:error, :not_found} ->
        db_take(id)
    end
  end

  ## Local (ETS) helpers

  def local_fetch(id) do
    case :ets.lookup(table(), id) do
      [{^id, layout, expires_at_ms}] ->
        if expired?(expires_at_ms) do
          :ets.delete(table(), id)
          {:error, :expired}
        else
          {:ok, layout}
        end

      [] ->
        {:error, :not_found}
    end
  end

  def local_take(id) do
    case local_fetch(id) do
      {:ok, layout} ->
        :ets.delete(table(), id)
        {:ok, layout}

      other ->
        other
    end
  end

  ## Database helpers

  defp persist_layout(id, layout, expires_at_ms) do
    now_utc = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    now_naive = DateTime.to_naive(now_utc) |> NaiveDateTime.truncate(:second)

    expires_at =
      expires_at_ms
      |> Kernel.*(1000)
      |> DateTime.from_unix!(:microsecond)

    record = %LayoutSessionRecord{
      id: id,
      layout: :erlang.term_to_binary(layout),
      expires_at: expires_at,
      inserted_at: now_naive
    }

    Repo.insert(record,
      on_conflict: [
        set: [layout: record.layout, expires_at: record.expires_at, inserted_at: now_naive]
      ],
      conflict_target: :id
    )
  rescue
    exception ->
      Logger.warning("LayoutStore persist failed: #{inspect(exception)}")
      :ok
  end

  defp db_fetch(id) do
    case Repo.get(LayoutSessionRecord, id) do
      nil ->
        {:error, :not_found}

      %LayoutSessionRecord{} = record ->
        if expired?(record.expires_at) do
          _ = delete_from_db(id)
          {:error, :expired}
        else
          with {:ok, layout} <- decode_layout(record.layout) do
            expires_at_ms = DateTime.to_unix(record.expires_at, :millisecond)
            :ets.insert(table(), {id, layout, expires_at_ms})
            {:ok, layout}
          end
        end
    end
  rescue
    exception ->
      Logger.warning("LayoutStore fetch failed: #{inspect(exception)}")
      {:error, :not_found}
  end

  defp db_take(id) do
    Repo.transaction(fn ->
      case Repo.get(LayoutSessionRecord, id) do
        nil ->
          {:error, :not_found}

        %LayoutSessionRecord{} = record ->
          cond do
            expired?(record.expires_at) ->
              _ = Repo.delete(record)
              {:error, :expired}

            true ->
              _ = Repo.delete(record)

              case decode_layout(record.layout) do
                {:ok, layout} -> {:ok, layout}
                {:error, _} = error -> error
              end
          end
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  rescue
    exception ->
      Logger.warning("LayoutStore take failed: #{inspect(exception)}")
      {:error, :not_found}
  end

  defp delete_from_db(id) do
    Repo.delete_all(from(r in LayoutSessionRecord, where: r.id == ^id))
  rescue
    _ -> :ok
  end

  defp decode_layout(binary) when is_binary(binary) do
    {:ok, :erlang.binary_to_term(binary)}
  rescue
    exception ->
      Logger.warning("LayoutStore decode failed: #{inspect(exception)}")
      {:error, :not_found}
  end

  ## Utilities

  defp expired?(expires_at) when is_integer(expires_at),
    do: expires_at <= System.system_time(:millisecond)

  defp expired?(%DateTime{} = expires_at),
    do: DateTime.compare(expires_at, DateTime.utc_now()) == :lt

  defp generate_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  defp table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])

      tid ->
        tid
    end
  end
end
