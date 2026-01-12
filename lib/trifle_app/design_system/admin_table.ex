defmodule TrifleApp.DesignSystem.AdminTable do
  use Phoenix.Component

  @doc """
  Renders an admin table with proper layout and styling for administration interfaces.
  """
  attr :class, :string, default: ""

  slot :header, required: true
  slot :body, required: true

  def admin_table(assigns) do
    ~H"""
    <div class={["px-4 sm:px-6 lg:px-8", @class]}>
      {render_slot(@header)}
      {render_slot(@body)}
    </div>
    """
  end

  @doc """
  Renders an admin table header with title, description, and optional actions.
  """
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :class, :string, default: ""

  slot :actions

  def admin_table_header(assigns) do
    ~H"""
    <div class={["sm:flex sm:items-center", @class]}>
      <div class="sm:flex-auto">
        <h1 class="text-base font-semibold leading-6 text-gray-900 dark:text-white">{@title}</h1>
        <%= if @description do %>
          <p class="mt-2 text-sm text-gray-700 dark:text-gray-300">{@description}</p>
        <% end %>
      </div>
      <%= if @actions != [] do %>
        <div class="mt-4 sm:ml-16 sm:mt-0 sm:flex-none">
          {render_slot(@actions)}
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the table container with proper overflow handling.
  """
  attr :class, :string, default: ""

  slot :inner_block, required: true

  def admin_table_container(assigns) do
    ~H"""
    <div class={["mt-8 flow-root", @class]}>
      <div class="-mx-4 -my-2 overflow-x-auto sm:-mx-6 lg:-mx-8">
        <div class="inline-block min-w-full py-2 align-middle sm:px-6 lg:px-8">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a full admin table with header and body sections.
  """
  attr :class, :string, default: ""

  slot :columns, required: true
  slot :rows, required: true

  def admin_table_full(assigns) do
    ~H"""
    <table class={["min-w-full divide-y divide-gray-300 dark:divide-gray-700", @class]}>
      <thead>
        <tr>
          <%= for column <- @columns do %>
            {render_slot(column)}
          <% end %>
        </tr>
      </thead>
      <tbody class="divide-y divide-gray-200 dark:divide-gray-600">
        {render_slot(@rows)}
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a table column header.
  """
  attr :class, :string, default: ""
  attr :first, :boolean, default: false
  attr :actions, :boolean, default: false

  slot :inner_block

  def admin_table_column(assigns) do
    ~H"""
    <%= if @actions do %>
      <th scope="col" class={["relative py-3.5 pl-3 pr-4 sm:pr-0", @class]}>
        <span class="sr-only">Actions</span>
      </th>
    <% else %>
      <th
        scope="col"
        class={[
          "py-3.5 text-left text-sm font-semibold text-gray-900 dark:text-white",
          if(@first, do: "pl-4 pr-3 sm:pl-0", else: "px-3"),
          @class
        ]}
      >
        {render_slot(@inner_block)}
      </th>
    <% end %>
    """
  end

  @doc """
  Renders a table cell with proper styling.
  """
  attr :class, :string, default: ""
  attr :first, :boolean, default: false
  attr :actions, :boolean, default: false

  slot :inner_block, required: true

  def admin_table_cell(assigns) do
    ~H"""
    <%= if @actions do %>
      <td class={[
        "relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-0",
        @class
      ]}>
        {render_slot(@inner_block)}
      </td>
    <% else %>
      <td class={[
        "whitespace-nowrap py-4 text-sm text-gray-500 dark:text-gray-300",
        if(@first, do: "pl-4 pr-3 font-medium text-gray-900 dark:text-white sm:pl-0", else: "px-3"),
        @class
      ]}>
        {render_slot(@inner_block)}
      </td>
    <% end %>
    """
  end

  @doc """
  Renders a status badge with consistent styling.
  """
  attr :variant, :string, default: "default"
  attr :class, :string, default: ""

  slot :inner_block, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={[status_badge_classes(@variant), @class]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  Renders an action button for table rows.
  """
  attr :variant, :string, default: "primary"
  attr :size, :string, default: "sm"
  attr :phx_click, :string, default: nil
  attr :phx_value_id, :string, default: nil
  attr :data_confirm, :string, default: nil
  attr :class, :string, default: ""

  slot :inner_block, required: true

  def table_action_button(assigns) do
    ~H"""
    <button
      phx-click={@phx_click}
      phx-value-id={@phx_value_id}
      data-confirm={@data_confirm}
      class={[table_action_button_classes(@variant), @class]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders pagination controls for admin tables.
  """
  attr :pagination, :map, required: true
  attr :path, :string, required: true
  attr :params, :list, default: []
  attr :class, :string, default: ""

  def admin_pagination(assigns) do
    ~H"""
    <div class={[
      "mt-6 flex flex-col gap-3 border-t border-gray-200 dark:border-gray-700 pt-4 sm:flex-row sm:items-center sm:justify-between",
      @class
    ]}>
      <div class="text-sm text-gray-600 dark:text-gray-300">
        Showing <span class="font-medium text-gray-900 dark:text-white">{@pagination.from}</span>
        to <span class="font-medium text-gray-900 dark:text-white">{@pagination.to}</span>
        of
        <span class="font-medium text-gray-900 dark:text-white">
          {@pagination.total_count}
        </span>
        results
      </div>

      <%= if @pagination.total_pages > 1 do %>
        <nav class="isolate inline-flex -space-x-px rounded-md shadow-sm" aria-label="Pagination">
          <%= if @pagination.has_prev do %>
            <.link
              patch={page_path(@path, @params, @pagination.prev_page)}
              class="relative inline-flex items-center rounded-l-md px-2.5 py-2 text-sm font-medium text-gray-600 hover:text-gray-900 dark:text-gray-300 dark:hover:text-white ring-1 ring-inset ring-gray-300 dark:ring-gray-600 hover:bg-gray-50 dark:hover:bg-slate-700 transition"
            >
              Prev
            </.link>
          <% else %>
            <span class="relative inline-flex items-center rounded-l-md px-2.5 py-2 text-sm font-medium text-gray-400 dark:text-gray-500 ring-1 ring-inset ring-gray-300 dark:ring-gray-600">
              Prev
            </span>
          <% end %>

          <%= for page <- @pagination.pages do %>
            <%= if page == :ellipsis do %>
              <span class="relative inline-flex items-center px-3 py-2 text-sm font-medium text-gray-500 dark:text-gray-400 ring-1 ring-inset ring-gray-300 dark:ring-gray-600">
                ...
              </span>
            <% else %>
              <%= if page == @pagination.page do %>
                <span
                  aria-current="page"
                  class="relative z-10 inline-flex items-center px-3.5 py-2 text-sm font-semibold text-white bg-teal-600 ring-1 ring-inset ring-teal-600"
                >
                  {page}
                </span>
              <% else %>
                <.link
                  patch={page_path(@path, @params, page)}
                  class="relative inline-flex items-center px-3.5 py-2 text-sm font-medium text-gray-700 hover:text-teal-700 dark:text-gray-300 dark:hover:text-teal-300 ring-1 ring-inset ring-gray-300 dark:ring-gray-600 hover:bg-gray-50 dark:hover:bg-slate-700 transition"
                >
                  {page}
                </.link>
              <% end %>
            <% end %>
          <% end %>

          <%= if @pagination.has_next do %>
            <.link
              patch={page_path(@path, @params, @pagination.next_page)}
              class="relative inline-flex items-center rounded-r-md px-2.5 py-2 text-sm font-medium text-gray-600 hover:text-gray-900 dark:text-gray-300 dark:hover:text-white ring-1 ring-inset ring-gray-300 dark:ring-gray-600 hover:bg-gray-50 dark:hover:bg-slate-700 transition"
            >
              Next
            </.link>
          <% else %>
            <span class="relative inline-flex items-center rounded-r-md px-2.5 py-2 text-sm font-medium text-gray-400 dark:text-gray-500 ring-1 ring-inset ring-gray-300 dark:ring-gray-600">
              Next
            </span>
          <% end %>
        </nav>
      <% end %>
    </div>
    """
  end

  # Helper functions for consistent styling
  defp status_badge_classes("success"),
    do:
      "inline-flex items-center rounded-md bg-green-50 dark:bg-green-900 px-2 py-1 text-xs font-medium text-green-700 dark:text-green-200 ring-1 ring-inset ring-green-600/20 dark:ring-green-500/30"

  defp status_badge_classes("error"),
    do:
      "inline-flex items-center rounded-md bg-red-50 dark:bg-red-900 px-2 py-1 text-xs font-medium text-red-700 dark:text-red-200 ring-1 ring-inset ring-red-600/20 dark:ring-red-500/30"

  defp status_badge_classes("warning"),
    do:
      "inline-flex items-center rounded-md bg-yellow-50 dark:bg-yellow-900 px-2 py-1 text-xs font-medium text-yellow-700 dark:text-yellow-200 ring-1 ring-inset ring-yellow-600/20 dark:ring-yellow-500/30"

  defp status_badge_classes("pending"),
    do:
      "inline-flex items-center rounded-md bg-yellow-50 dark:bg-yellow-900 px-2 py-1 text-xs font-medium text-yellow-700 dark:text-yellow-200 ring-1 ring-inset ring-yellow-600/20 dark:ring-yellow-500/30"

  defp status_badge_classes("admin"),
    do:
      "inline-flex items-center rounded-md bg-teal-50 dark:bg-teal-900 px-2 py-1 text-xs font-medium text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30"

  defp status_badge_classes(_),
    do:
      "inline-flex items-center rounded-md bg-gray-50 dark:bg-gray-800 px-2 py-1 text-xs font-medium text-gray-600 dark:text-gray-300 ring-1 ring-inset ring-gray-500/10 dark:ring-gray-400/20"

  defp table_action_button_classes("primary"),
    do: "text-teal-600 hover:text-teal-900 dark:text-teal-400 dark:hover:text-teal-300"

  defp table_action_button_classes("danger"),
    do: "text-red-600 hover:text-red-900 dark:text-red-400 dark:hover:text-red-300"

  defp table_action_button_classes(_),
    do: "text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-300"

  defp page_path(path, params, page) do
    params =
      params
      |> Keyword.delete(:page)
      |> maybe_add_page(page)

    query = URI.encode_query(params)

    if query == "" do
      path
    else
      path <> "?" <> query
    end
  end

  defp maybe_add_page(params, page) when is_integer(page) and page > 1,
    do: Keyword.put(params, :page, page)

  defp maybe_add_page(params, _page), do: params
end
