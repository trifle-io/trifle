defmodule TrifleApp.Exports.LayoutStore do
  @moduledoc """
  Ephemeral ETS-backed storage for export layouts during headless rendering.

  Layouts are kept in-memory for a short period (default 60s) so that Chrome
  can retrieve them via a signed token without bloating query strings.
  """

  @table :trifle_export_layouts
  @ttl_ms 60_000

  @type layout_id :: String.t()

  @doc """
  Stores the given layout for a limited time and returns its storage ID.
  """
  @spec put(TrifleApp.Exports.Layout.t(), Keyword.t()) :: layout_id()
  def put(layout, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, @ttl_ms)
    id = generate_id()
    expires_at = System.system_time(:millisecond) + ttl

    :ets.insert(table(), {id, layout, expires_at})
    id
  end

  @doc """
  Retrieves a layout by ID without removing it.
  """
  @spec fetch(layout_id()) ::
          {:ok, TrifleApp.Exports.Layout.t()} | {:error, :not_found | :expired}
  def fetch(id) do
    case :ets.lookup(table(), id) do
      [{^id, layout, expires_at}] ->
        if expired?(expires_at) do
          :ets.delete(table(), id)
          {:error, :expired}
        else
          {:ok, layout}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Retrieves and deletes the layout if it is still valid.
  """
  @spec take(layout_id()) ::
          {:ok, TrifleApp.Exports.Layout.t()} | {:error, :not_found | :expired}
  def take(id) do
    with {:ok, layout} <- fetch(id) do
      :ets.delete(table(), id)
      {:ok, layout}
    end
  end

  defp expired?(expires_at), do: expires_at <= System.system_time(:millisecond)

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
