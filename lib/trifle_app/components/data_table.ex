defmodule TrifleApp.Components.DataTable do
  @moduledoc false

  use TrifleApp, :html

  alias TrifleApp.ExploreLive

  @type table_dataset :: %{
          optional(:id) => any(),
          rows: list(),
          columns: list(),
          values: map(),
          color_paths: list(),
          granularity: any(),
          empty_message: String.t()
        }

  attr :dataset, :map, required: true
  attr :transponder_info, :map, default: %{}
  attr :outer_class, :string, default: nil
  attr :scroll_class, :string, default: nil
  attr :table_class, :string, default: nil

  def table(assigns) do
    dataset = assigns.dataset || %{}

    rows =
      dataset
      |> Map.get(:rows, [])
      |> Enum.map(fn row ->
        %{
          path: to_string(Map.get(row, :path, "")),
          display_path: normalize_display_path(Map.get(row, :display_path), Map.get(row, :path)),
          index: Map.get(row, :index) || 0
        }
      end)

    columns =
      dataset
      |> Map.get(:columns, [])
      |> Enum.map(fn column ->
        %{at: Map.get(column, :at), index: Map.get(column, :index) || 0}
      end)

    color_paths =
      dataset
      |> Map.get(:color_paths, [])
      |> case do
        [] -> Enum.map(rows, &(&1.display_path || &1.path || ""))
        list -> list
      end

    table_base_id = dataset_dom_id(dataset)

    assigns =
      assigns
      |> assign(:rows, rows)
      |> assign(:columns, columns)
      |> assign(:values, Map.get(dataset, :values, %{}))
      |> assign(:color_paths, color_paths)
      |> assign(:granularity, Map.get(dataset, :granularity))
      |> assign(:empty_message, Map.get(dataset, :empty_message, "No data available yet."))
      |> assign(:has_grid, rows != [] and columns != [])
      |> assign(:table_dom_id, table_base_id <> "-table")
      |> assign(:scroll_dom_id, table_base_id <> "-scroll")
      |> assign(:container_dom_id, table_base_id <> "-container")

    ~H"""
    <div
      class={[
        "data-table-shell flex-1 flex flex-col min-h-0",
        @outer_class
      ]}
      phx-hook="PhantomRows"
      data-role="table-container"
      id={@container_dom_id}
    >
      <div
        class={[
          "data-table-scroll flex-1 overflow-x-auto overflow-y-auto relative",
          @scroll_class
        ]}
        id={@scroll_dom_id}
        data-role="table-scroll"
        phx-hook="TableHover"
      >
        <%= if @has_grid do %>
          <table
            class={[
              "min-w-full divide-y divide-gray-300 dark:divide-slate-600 overflow-auto",
              @table_class
            ]}
            id={@table_dom_id}
            data-role="data-table"
            phx-hook="FastTooltip"
            style="table-layout: fixed;"
          >
            <thead>
              <tr>
                <th
                  scope="col"
                  class="top-0 lg:left-0 lg:sticky whitespace-nowrap py-2 pl-4 pr-3 text-left text-xs font-semibold text-gray-900 dark:text-white h-16 z-20 border-r border-gray-300 dark:border-slate-600 lg:border-r-0 lg:shadow-[1px_0_2px_-1px_rgba(209,213,219,0.8)] dark:lg:shadow-[1px_0_2px_-1px_rgba(71,85,105,0.8)] bg-white dark:bg-slate-800"
                  style="width: 200px;"
                >
                  Path
                </th>
                <%= for %{at: at, index: idx} <- @columns do %>
                  <th
                    scope="col"
                    class="top-0 sticky whitespace-nowrap px-2 py-2 text-left text-xs font-mono font-semibold text-teal-700 dark:text-teal-400 bg-white dark:bg-slate-800 h-16 align-top z-10 transition-colors duration-150"
                    data-col={idx}
                    style="width: 120px;"
                  >
                    {ExploreLive.format_table_timestamp(at, @granularity)}
                  </th>
                <% end %>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-200 dark:divide-slate-700 bg-white dark:bg-slate-800">
              <%= for row <- @rows do %>
                <tr data-row={row.index}>
                  <td
                    class="lg:left-0 lg:sticky bg-white dark:bg-slate-800 whitespace-nowrap py-1 pl-4 pr-3 text-xs font-mono text-gray-900 dark:text-white z-10 transition-colors duration-150 border-r border-gray-300 dark:border-slate-600 lg:border-r-0 lg:shadow-[1px_0_2px_-1px_rgba(209,213,219,0.8)] dark:lg:shadow-[1px_0_2px_-1px_rgba(71,85,105,0.8)]"
                    data-row={row.index}
                  >
                    {ExploreLive.format_nested_path(
                      row.display_path,
                      @color_paths,
                      @transponder_info,
                      transponder_path: row.path,
                      display_path: row.display_path
                    )}
                  </td>
                  <%= for %{at: at, index: col_index} <- @columns do %>
                    <% value = Map.get(@values, {row.path, at}) %>
                    <%= if value do %>
                      <td
                        class="whitespace-nowrap px-2 py-1 text-xs font-medium text-gray-900 dark:text-white transition-colors duration-150 cursor-pointer"
                        data-row={row.index}
                        data-col={col_index}
                      >
                        {value}
                      </td>
                    <% else %>
                      <td
                        class="whitespace-nowrap px-2 py-1 text-xs font-medium text-gray-300 dark:text-slate-500 transition-colors duration-150 cursor-pointer"
                        data-row={row.index}
                        data-col={col_index}
                      >
                        0
                      </td>
                    <% end %>
                  <% end %>
                </tr>
              <% end %>
            </tbody>
          </table>
          <div class="border-t border-gray-200 dark:border-slate-700" data-role="table-border"></div>
        <% else %>
          <div class="h-full w-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 px-6 text-center">
            {@empty_message}
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def from_stats(stats, opts \\ []) do
    paths = opts |> Keyword.get(:paths, stats_paths(stats)) |> normalize_paths()

    display_overrides =
      opts
      |> Keyword.get(:display_paths, %{})
      |> Enum.reduce(%{}, fn {path, display}, acc ->
        Map.put(acc, to_string(path), normalize_display_path(display, path))
      end)

    reverse_cols? = Keyword.get(opts, :reverse_columns, true)

    at_list =
      stats
      |> stats_at()
      |> maybe_reverse(reverse_cols?)
      |> Enum.with_index(1)
      |> Enum.map(fn {at, idx} -> %{at: at, index: idx} end)

    rows =
      paths
      |> Enum.uniq()
      |> Enum.with_index(1)
      |> Enum.map(fn {path, idx} ->
        string_path = to_string(path)
        display_path = Map.get(display_overrides, string_path, string_path)

        %{
          path: string_path,
          display_path: normalize_display_path(display_path, path),
          index: idx
        }
      end)

    %{
      rows: rows,
      columns: at_list,
      values: stats_values(stats),
      color_paths:
        Keyword.get(opts, :color_paths, Enum.map(rows, &(&1.display_path || &1.path || ""))),
      granularity: Keyword.get(opts, :granularity),
      empty_message: Keyword.get(opts, :empty_message, "No data available yet.")
    }
    |> maybe_put_id(Keyword.get(opts, :id))
  end

  defp normalize_paths(list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp normalize_paths(other), do: normalize_paths(List.wrap(other))

  defp stats_paths(%{paths: paths}) when is_list(paths), do: paths
  defp stats_paths(%{"paths" => paths}) when is_list(paths), do: paths
  defp stats_paths(_), do: []

  defp stats_at(%{at: at}) when is_list(at), do: at
  defp stats_at(%{"at" => at}) when is_list(at), do: at
  defp stats_at(_), do: []

  defp stats_values(%{values: values}) when is_map(values), do: values
  defp stats_values(%{"values" => values}) when is_map(values), do: values
  defp stats_values(_), do: %{}

  defp maybe_reverse(list, true), do: Enum.reverse(list)
  defp maybe_reverse(list, _), do: list

  defp normalize_display_path(nil, fallback), do: to_string(fallback || "")

  defp normalize_display_path(display, fallback) do
    display
    |> to_string()
    |> String.trim()
    |> case do
      "" -> to_string(fallback || "")
      value -> value
    end
  end

  defp maybe_put_id(map, nil), do: map
  defp maybe_put_id(map, id), do: Map.put(map, :id, id)

  defp dataset_dom_id(dataset) do
    base =
      dataset
      |> Map.get(:id) ||
        Map.get(dataset, "id") ||
        "data-table"

    base
    |> to_string()
    |> String.trim()
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "-")
    |> case do
      "" -> "data-table"
      value -> value
    end
  end
end
