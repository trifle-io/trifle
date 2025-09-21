defmodule TrifleApp.DesignSystem.FormField do
  use Phoenix.Component

  @doc """
  Renders a standardized form field with label, input, and error handling.

  ## Examples

      <.form_field field={@form[:email]} label="Email" type="email" required />
      
      <.form_field field={@form[:description]} type="textarea" label="Description" 
                   help_text="Optional description for this item" />
      
      <.form_field field={@form[:status]} type="select" label="Status" 
                   options={[{"Active", "active"}, {"Inactive", "inactive"}]} 
                   prompt="Choose status..." />
  """
  attr :field, Phoenix.HTML.FormField, required: true

  attr :type, :string,
    default: "text",
    values: ~w(text email password number textarea select checkbox hidden)

  attr :label, :string, required: true
  attr :help_text, :string, default: nil
  attr :required, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :class, :string, default: ""
  attr :options, :list, default: []
  attr :prompt, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :rows, :integer, default: 4

  def form_field(assigns) do
    ~H"""
    <div class={["space-y-2", @class]}>
      <!-- Label -->
      <.form_label for={@field.id} required={@required}>
        {@label}
      </.form_label>
      
    <!-- Input -->
      <div class="relative">
        <%= case @type do %>
          <% "select" -> %>
            <div class="grid grid-cols-1">
              <select
                id={@field.id}
                name={@field.name}
                class={[
                  "col-start-1 row-start-1 w-full appearance-none rounded-lg bg-white dark:bg-slate-700 py-2 pr-8 pl-3 text-base text-gray-900 dark:text-white outline-1 -outline-offset-1 outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm",
                  @field.errors != [] && "outline-red-400 focus:outline-red-400"
                ]}
                disabled={@disabled}
              >
                <%= if @prompt do %>
                  <option value="">{@prompt}</option>
                <% end %>
                <%= for {label, value} <- @options do %>
                  <option value={value} selected={to_string(value) == to_string(@field.value)}>
                    {label}
                  </option>
                <% end %>
              </select>
              
    <!-- Dropdown arrow -->
              <svg
                class="col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-400 dark:text-slate-500 sm:h-4 sm:w-4"
                viewBox="0 0 16 16"
                fill="currentColor"
                aria-hidden="true"
              >
                <path
                  fill-rule="evenodd"
                  d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z"
                  clip-rule="evenodd"
                />
              </svg>
            </div>
          <% "textarea" -> %>
            <textarea
              id={@field.id}
              name={@field.name}
              rows={@rows}
              placeholder={@placeholder}
              class={[
                "block w-full rounded-lg border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-700 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm resize-y",
                @field.errors != [] && "border-red-400 focus:border-red-400 focus:ring-red-400"
              ]}
              disabled={@disabled}
            ><%= @field.value %></textarea>
          <% "checkbox" -> %>
            <div class="flex items-center">
              <input type="hidden" name={@field.name} value="false" />
              <input
                type="checkbox"
                id={@field.id}
                name={@field.name}
                value="true"
                checked={@field.value}
                class="h-4 w-4 rounded border-gray-300 dark:border-slate-600 text-teal-600 focus:ring-teal-500"
                disabled={@disabled}
              />
            </div>
          <% type when type in ~w(text email password number hidden) -> %>
            <input
              type={@type}
              id={@field.id}
              name={@field.name}
              value={@field.value}
              placeholder={@placeholder}
              class={[
                "block w-full rounded-lg border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-700 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm",
                @field.errors != [] && "border-red-400 focus:border-red-400 focus:ring-red-400",
                @type == "hidden" && "sr-only"
              ]}
              required={@required}
              disabled={@disabled}
            />
        <% end %>
      </div>
      
    <!-- Help Text -->
      <%= if @help_text do %>
        <p class="text-sm text-gray-500 dark:text-slate-400">
          {@help_text}
        </p>
      <% end %>
      
    <!-- Errors -->
      <.form_errors field={@field} />
    </div>
    """
  end

  @doc """
  Renders a form label with optional required indicator.
  """
  attr :for, :string, required: true
  attr :required, :boolean, default: false
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def form_label(assigns) do
    ~H"""
    <label for={@for} class={["block text-sm font-medium text-gray-700 dark:text-slate-300", @class]}>
      {render_slot(@inner_block)}
      <%= if @required do %>
        <span class="text-red-500 ml-1">*</span>
      <% end %>
    </label>
    """
  end

  @doc """
  Renders field errors with consistent styling.
  """
  attr :field, Phoenix.HTML.FormField, required: true

  def form_errors(assigns) do
    ~H"""
    <div :if={@field.errors != []} class="space-y-1">
      <%= for error <- @field.errors do %>
        <div class="flex items-center gap-2 text-sm text-red-600 dark:text-red-400">
          <svg class="h-4 w-4 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
            <path
              fill-rule="evenodd"
              d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-8-3a1 1 0 00-.867.5 1 1 0 11-1.731-1A3 3 0 0113 8a3.001 3.001 0 01-2 2.83V11a1 1 0 11-2 0v-1a1 1 0 011-1 1 1 0 100-2zm0 8a1 1 0 100-2 1 1 0 000 2z"
              clip-rule="evenodd"
            />
          </svg>
          <span>{translate_error(error)}</span>
        </div>
      <% end %>
    </div>
    """
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  defp translate_error(msg), do: msg
end
