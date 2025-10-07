defmodule TrifleApp.DatabaseTranspondersLive do
  use TrifleApp, :live_view

  alias TrifleApp.TranspondersComponents
  alias TrifleApp.TranspondersLive.Shared

  @impl true
  def mount(params, _session, socket) do
    case Shared.resolve_database_source(params, socket.assigns) do
      {:ok, source_assigns} ->
        socket =
          socket
          |> Shared.assign_initial(source_assigns)
          |> Shared.assign_paths()
          |> assign(:nav_section, :databases)

        {:ok, socket}

      {:redirect, to} ->
        {:ok, redirect(socket, to: to)}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, Shared.apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_info({TrifleApp.TranspondersLive.FormComponent, {:saved, transponder}}, socket) do
    Shared.handle_form_saved(socket, transponder)
  end

  @impl true
  def handle_info({TrifleApp.TranspondersLive.FormComponent, {:updated, transponder}}, socket) do
    Shared.handle_form_updated(socket, transponder)
  end

  @impl true
  def handle_event("delete_transponder", params, socket) do
    Shared.handle_delete(socket, params)
  end

  def handle_event("toggle_transponder", params, socket) do
    Shared.handle_toggle(socket, params)
  end

  def handle_event("duplicate_transponder", params, socket) do
    Shared.handle_duplicate(socket, params)
  end

  def handle_event("reorder_transponders", params, socket) do
    Shared.handle_reorder(socket, params)
  end

  def handle_event("transponder_clicked", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: socket.assigns.show_path.(id))}
  end

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col dark:bg-slate-900 min-h-screen">
      <div class="space-y-6">
        <div class="sm:p-4">
          <div class="border-b border-gray-200 dark:border-slate-700">
            <nav class="-mb-px flex space-x-4 sm:space-x-8" aria-label="Database tabs">
              <.link
                navigate={@index_path}
                class="group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium border-teal-500 text-teal-600 dark:text-teal-300"
                aria-current="page"
              >
                <svg
                  class="text-teal-400 group-hover:text-teal-500 -ml-0.5 mr-2 h-5 w-5"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M21 7.5l-2.25-1.313M21 7.5v2.25m0-2.25l-2.25 1.313M3 7.5l2.25-1.313M3 7.5l2.25 1.313M3 7.5v2.25m9 3l2.25-1.313M12 12.75l-2.25-1.313M12 12.75V15m0 6.75l2.25-1.313M12 21.75V19.5m0 2.25l-2.25-1.313m0-16.875L12 2.25l2.25 1.313M21 14.25v2.25l-2.25 1.313m-13.5 0L3 16.5v-2.25"
                  />
                </svg>
                <span class="hidden sm:block">Transponders</span>
              </.link>

              <%= if @settings_path do %>
                <.link
                  navigate={@settings_path}
                  class="group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium border-transparent text-gray-500 dark:text-slate-400 hover:border-gray-300 dark:hover:border-slate-500 hover:text-gray-700 dark:hover:text-slate-300"
                >
                  <svg
                    class="text-gray-400 dark:text-slate-400 group-hover:text-gray-500 dark:group-hover:text-slate-300 -ml-0.5 mr-2 h-5 w-5"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M11.42 15.17L17.25 21A2.652 2.652 0 0021 17.25l-5.877-5.877M11.42 15.17l2.496-3.03c.317-.384.74-.626 1.208-.766M11.42 15.17l-4.655 5.653a2.548 2.548 0 11-3.586-3.586l6.837-5.63m5.108-.233c.55-.164 1.163-.188 1.743-.14a4.5 4.5 0 004.486-6.336l-3.276 3.277a3.004 3.004 0 01-2.25-2.25l3.276-3.276a4.5 4.5 0 00-6.336 4.486c.091 1.076-.071 2.264-.904 2.95l-.102.085m-1.745 1.437L5.909 7.5H4.5L2.25 3.75l1.5-1.5L7.5 4.5v1.409l4.26 4.26m-1.745 1.437l1.745-1.437m6.615 8.206L15.75 15.75M4.867 19.125h.008v.008h-.008v-.008z"
                    />
                  </svg>
                  <span class="hidden sm:block">Settings</span>
                </.link>
              <% end %>
            </nav>
          </div>
        </div>

        <TranspondersComponents.transponder_list
          transponders_stream={@streams.transponders}
          transponders_empty={@transponders_empty}
          new_path={@new_path}
          show_path={@show_path}
          edit_path={@edit_path}
        />
      </div>

      <TranspondersComponents.transponder_form_modal
        ui_action={@ui_action}
        transponder={@transponder}
        cancel_path={@cancel_path}
        source={@source}
        source_type={@source_type}
      />

      <TranspondersComponents.transponder_details_modal
        ui_action={@ui_action}
        transponder={@transponder}
        cancel_path={@cancel_path}
        source={@source}
      />
    </div>
    """
  end
end
