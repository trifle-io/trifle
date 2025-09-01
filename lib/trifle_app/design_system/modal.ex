defmodule TrifleApp.DesignSystem.Modal do
  use Phoenix.Component

  @doc """
  Renders a modal dialog with consistent styling.
  
  ## Examples
  
      <.app_modal id="error-modal" show={@show_modal} on_cancel="hide_modal">
        <:title>Transponder Errors</:title>
        <:body>
          Error details go here...
        </:body>
        <:actions>
          <.button phx-click="hide_modal">Close</.button>
        </:actions>
      </.app_modal>
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, :string, default: nil
  attr :size, :string, default: "md", values: ["sm", "md", "lg", "xl"]

  slot :title, required: true
  slot :body, required: true
  slot :actions

  def app_modal(assigns) do
    ~H"""
    <div
      :if={@show}
      id={@id}
      class="fixed inset-0 z-50 overflow-y-auto"
      aria-labelledby={"#{@id}-title"}
      aria-modal="true"
      role="dialog"
    >
      <div class="flex min-h-full items-end justify-center p-4 text-center sm:items-center sm:p-0">
        <div class="fixed inset-0 bg-gray-500 bg-opacity-75 dark:bg-slate-900 dark:bg-opacity-80 transition-opacity"></div>
        
        <div class={[
          "relative transform overflow-hidden rounded-lg bg-white dark:bg-slate-800 px-4 pb-4 pt-5 text-left shadow-xl transition-all sm:my-8 sm:p-6",
          modal_size_classes(@size)
        ]}>
          <!-- Close button -->
          <%= if @on_cancel do %>
            <div class="absolute right-0 top-0 pr-4 pt-4">
              <button
                type="button"
                phx-click={@on_cancel}
                class="rounded-md bg-white dark:bg-slate-800 text-gray-400 dark:text-slate-500 hover:text-gray-500 dark:hover:text-slate-400 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:ring-offset-2 dark:focus:ring-offset-slate-800"
              >
                <span class="sr-only">Close</span>
                <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          <% end %>

          <!-- Title -->
          <div class="sm:flex sm:items-start">
            <div class="mt-3 w-full text-center sm:ml-0 sm:mt-0 sm:text-left">
              <h3 class="text-base font-semibold leading-6 text-gray-900 dark:text-white" id={"#{@id}-title"}>
                <%= render_slot(@title) %>
              </h3>
            </div>
          </div>

          <!-- Body -->
          <div class="mt-4">
            <%= render_slot(@body) %>
          </div>

          <!-- Actions -->
          <%= if @actions != [] do %>
            <div class="mt-5 sm:mt-6 sm:grid sm:grid-flow-row-dense sm:grid-cols-2 sm:gap-3">
              <%= render_slot(@actions) %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp modal_size_classes(size) do
    case size do
      "sm" -> "sm:max-w-lg sm:w-full"
      "md" -> "sm:max-w-2xl sm:w-full"
      "lg" -> "sm:max-w-4xl sm:w-full"
      "xl" -> "sm:max-w-6xl sm:w-full"
    end
  end
end