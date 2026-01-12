defmodule TrifleApp.TranspondersComponents do
  @moduledoc """
  Shared function components for rendering transponder UIs.
  """

  use TrifleApp, :html
  alias TrifleApp.TranspondersLive.DetailsComponent
  alias TrifleApp.TranspondersLive.FormComponent

  attr :transponders_stream, :any, required: true
  attr :transponders_empty, :boolean, required: true
  attr :new_path, :string, required: true
  attr :show_path, :any, required: true
  attr :edit_path, :any, required: true

  def transponder_list(assigns) do
    ~H"""
    <div class="px-4 pb-6 sm:px-6 lg:px-8">
      <div class="bg-white dark:bg-slate-800 rounded-lg shadow">
        <div class="flex items-center justify-between border-b border-gray-100 px-4 py-3.5 text-sm font-semibold text-gray-900 sm:px-6 dark:border-slate-700 dark:text-white">
          <div class="flex items-center gap-2">
            <span>Transponders</span>
            <span class="inline-flex items-center rounded-md bg-teal-50 dark:bg-teal-900 px-2 py-1 text-xs font-medium text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30">
              {Enum.count(@transponders_stream)}
            </span>
          </div>
          <.link
            patch={@new_path}
            class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
          >
            <svg class="h-5 w-5 md:-ml-0.5 md:mr-1.5" viewBox="0 0 20 20" fill="currentColor">
              <path d="M10.75 4.75a.75.75 0 00-1.5 0v4.5h-4.5a.75.75 0 000 1.5h4.5v4.5a.75.75 0 001.5 0v-4.5h4.5a.75.75 0 000-1.5h-4.5v-4.5z" />
            </svg>
            <span class="hidden md:inline">New Transponder</span>
          </.link>
        </div>

        <div class="divide-y divide-gray-100 dark:divide-slate-700">
          <%= if @transponders_empty do %>
            <div class="py-12 text-center">
              <svg
                class="mx-auto h-12 w-12 text-gray-400 dark:text-gray-500"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                aria-hidden="true"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M21 7.5l-2.25-1.313M21 7.5v2.25m0-2.25l-2.25 1.313M3 7.5l2.25-1.313M3 7.5l2.25 1.313M3 7.5v2.25m9 3l2.25-1.313M12 12.75l-2.25-1.313M12 12.75V15m0 6.75l2.25-1.313M12 21.75V19.5m0 2.25l-2.25-1.313m0-16.875L12 2.25l2.25 1.313M21 14.25v2.25l-2.25 1.313m-13.5 0L3 16.5v-2.25"
                />
              </svg>
              <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
                No transponders
              </h3>
              <p class="mt-1 text-sm text-gray-500 dark:text-slate-400">
                Get started by creating a new transponder.
              </p>
            </div>
          <% end %>

          <div
            id="transponders"
            phx-update="stream"
            phx-hook="Sortable"
            data-group="transponders"
            data-handle=".drag-handle"
            class={[@transponders_empty && "hidden"]}
          >
            <%= for {dom_id, transponder} <- @transponders_stream do %>
              <div
                id={dom_id}
                class="px-4 py-4 sm:px-6 group border-b border-gray-100 dark:border-slate-700 last:border-b-0 cursor-pointer hover:bg-gray-50 dark:hover:bg-slate-700/50"
                data-id={transponder.id}
                phx-click="transponder_clicked"
                phx-value-id={transponder.id}
              >
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-3">
                    <div class="flex-shrink-0 text-gray-400 dark:text-slate-500 text-lg font-medium min-w-[2rem] text-center">
                      {transponder.order + 1}
                    </div>

                    <div class="min-w-0 flex-1">
                      <div class="flex items-center mb-1">
                        <.link
                          patch={@show_path.(transponder.id)}
                          class="text-sm font-medium text-gray-900 dark:text-white hover:text-teal-600 dark:hover:text-teal-400"
                        >
                          {transponder.name || transponder.key}
                        </.link>
                      </div>
                      <p class="text-xs text-gray-500 dark:text-slate-400">
                        Key Pattern:
                        <code class="bg-gray-100 dark:bg-slate-700 px-1 py-0.5 rounded font-mono">
                          {transponder.key}
                        </code>
                        <span class="mx-3">•</span>
                        Response Path:
                        <code class="bg-gray-100 dark:bg-slate-700 px-1 py-0.5 rounded font-mono">
                          {Map.get(transponder.config, "response_path", "N/A")}
                        </code>
                      </p>
                    </div>
                  </div>

                  <div class="flex items-center gap-2" phx-click="noop">
                    <div class="flex items-center gap-2 opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none group-hover:pointer-events-auto">
                      <button
                        type="button"
                        phx-click="duplicate_transponder"
                        phx-value-id={transponder.id}
                        title="Duplicate"
                        aria-label="Duplicate transponder"
                        class="inline-flex items-center justify-center rounded-md border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-800 p-1.5 text-xs text-gray-700 dark:text-slate-200 hover:bg-gray-50 dark:hover:bg-slate-700"
                      >
                        <svg
                          xmlns="http://www.w3.org/2000/svg"
                          fill="none"
                          viewBox="0 0 24 24"
                          stroke-width="1.5"
                          stroke="currentColor"
                          class="h-5 w-5"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            d="M15.75 17.25v3.375c0 .621-.504 1.125-1.125 1.125h-9.75a1.125 1.125 0 0 1-1.125-1.125V7.875c0-.621.504-1.125 1.125-1.125H6.75a9.06 9.06 0 0 1 1.5.124m7.5 10.376h3.375c.621 0 1.125-.504 1.125-1.125V11.25c0-4.46-3.243-8.161-7.5-8.876a9.06 9.06 0 0 0-1.5-.124H9.375c-.621 0-1.125.504-1.125 1.125v3.5m7.5 10.375H9.375a1.125 1.125 0 0 1-1.125-1.125v-9.25m12 6.625v-1.875a3.375 3.375 0 0 0-3.375-3.375h-1.5a1.125 1.125 0 0 1-1.125-1.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H9.75"
                          />
                        </svg>
                      </button>

                      <.link
                        patch={@edit_path.(transponder.id)}
                        title="Edit"
                        aria-label="Edit transponder"
                        class="inline-flex items-center justify-center rounded-md border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-800 p-1.5 text-xs text-gray-700 dark:text-slate-200 hover:bg-gray-50 dark:hover:bg-slate-700"
                      >
                        <svg
                          xmlns="http://www.w3.org/2000/svg"
                          fill="none"
                          viewBox="0 0 24 24"
                          stroke-width="1.5"
                          stroke="currentColor"
                          class="h-5 w-5"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0115.75 21h-9.5A2.25 2.25 0 014 18.75v-9.5A2.25 2.25 0 016.25 7h4.75"
                          />
                        </svg>
                      </.link>

                      <button
                        type="button"
                        phx-click="delete_transponder"
                        phx-value-id={transponder.id}
                        data-confirm="Are you sure you want to delete this transponder?"
                        title="Delete"
                        aria-label="Delete transponder"
                        class="inline-flex items-center justify-center rounded-md border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-800 p-1.5 text-xs text-red-600 dark:text-red-400 hover:bg-gray-50 dark:hover:bg-slate-700"
                      >
                        <svg
                          xmlns="http://www.w3.org/2000/svg"
                          fill="none"
                          viewBox="0 0 24 24"
                          stroke-width="1.5"
                          stroke="currentColor"
                          class="h-5 w-5"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0"
                          />
                        </svg>
                      </button>
                    </div>

                    <button
                      type="button"
                      phx-click="toggle_transponder"
                      phx-value-id={transponder.id}
                      class={[
                        "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-teal-600 focus:ring-offset-2 dark:focus:ring-offset-slate-800",
                        if(transponder.enabled,
                          do: "bg-teal-600",
                          else: "bg-gray-200 dark:bg-slate-600"
                        )
                      ]}
                    >
                      <span class="sr-only">Toggle transponder</span>
                      <span class={[
                        "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                        if(transponder.enabled, do: "translate-x-5", else: "translate-x-0")
                      ]} />
                    </button>

                    <div
                      class="drag-handle cursor-move text-gray-400 dark:text-slate-500 hover:text-gray-600 dark:hover:text-slate-300"
                      phx-click="noop"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        class="h-5 w-5"
                      >
                        <path stroke-linecap="round" stroke-linejoin="round" d="M3 8h18M3 16h18" />
                      </svg>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :ui_action, :atom, required: true
  attr :transponder, :any
  attr :cancel_path, :string, required: true
  attr :source, :any, required: true
  attr :source_type, :atom, required: true
  attr :modal_id, :string, default: "transponder-modal"

  def transponder_form_modal(assigns) do
    ~H"""
    <.app_modal
      :if={@ui_action in [:new, :edit]}
      id={@modal_id}
      show
      on_cancel={JS.patch(@cancel_path)}
    >
      <:title>{if @ui_action == :new, do: "New Transponder", else: "Edit Transponder"}</:title>
      <:body>
        <.live_component
          module={FormComponent}
          id={@transponder.id || :new}
          title={if @ui_action == :new, do: "New Transponder", else: "Edit Transponder"}
          action={@ui_action}
          transponder={@transponder}
          source={@source}
          source_type={@source_type}
          patch={@cancel_path}
        />
      </:body>
    </.app_modal>
    """
  end

  attr :ui_action, :atom, required: true
  attr :transponder, :any
  attr :cancel_path, :string, required: true
  attr :source, :any, required: true
  attr :modal_id, :string, default: "transponder-details-modal"

  def transponder_details_modal(assigns) do
    ~H"""
    <.app_modal :if={@ui_action == :show} id={@modal_id} show on_cancel={JS.patch(@cancel_path)}>
      <:title>Transponder Details</:title>
      <:body>
        <.live_component
          module={DetailsComponent}
          id={@transponder.id}
          transponder={@transponder}
          source={@source}
          patch={@cancel_path}
        />
      </:body>
    </.app_modal>
    """
  end
end
