defmodule TrifleApp.ProjectTranspondersLive do
  use TrifleApp, :live_view

  alias TrifleApp.TranspondersComponents
  alias TrifleApp.TranspondersLive.Shared

  @impl true
  def mount(params, _session, socket) do
    case Shared.resolve_project_source(params, socket.assigns) do
      {:ok, source_assigns} ->
        socket =
          socket
          |> Shared.assign_initial(source_assigns)
          |> Shared.assign_paths()

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
          <.project_nav project={@project} current={:transponders} />
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
