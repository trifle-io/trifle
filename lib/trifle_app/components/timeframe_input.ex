defmodule TrifleApp.Components.TimeframeInput do
  @moduledoc false

  use Phoenix.Component

  import TrifleApp.CoreComponents, only: [translate_error: 1]

  alias Trifle.Timeframe

  attr :field, Phoenix.HTML.FormField
  attr :label, :string, default: nil
  attr :placeholder, :string, default: "e.g. 1h, 1d, 1w"
  attr :help, :string, default: nil
  attr :id, :string
  attr :name, :string
  attr :value, :string, default: ""
  attr :disabled, :boolean, default: false

  attr :input_class, :string,
    default:
      "block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"

  attr :wrapper_class, :string, default: ""

  attr :rest, :global,
    include: ~w(autocomplete autocapitalize autocorrect spellcheck phx-debounce phx-hook phx-target inputmode)

  def timeframe_input(assigns) do
    assigns =
      case assigns do
        %{field: %Phoenix.HTML.FormField{} = field} ->
          assigns
          |> assign(:field, nil)
          |> assign_new(:id, fn -> field.id end)
          |> assign(:name, field.name)
          |> assign(:value, field.value || "")
          |> assign(:errors, Enum.map(field.errors, &translate_error/1))

        _ ->
          assigns
          |> assign_new(:errors, fn -> [] end)
      end

    if is_nil(assigns.name) do
      raise ArgumentError,
            "timeframe_input expects either a :field or a :name attribute"
    end

    status = Timeframe.status(assigns.value)
    assigns = assign(assigns, :status, status)

    ~H"""
    <div class={@wrapper_class}>
      <label :if={@label} class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
        {@label}
      </label>
      <input
        type="text"
        id={@id}
        name={@name}
        value={@value || ""}
        placeholder={@placeholder}
        class={[
          @input_class,
          @disabled &&
            "bg-gray-100 dark:bg-slate-700 text-gray-500 dark:text-slate-400 cursor-not-allowed"
        ]}
        disabled={@disabled}
        {@rest}
      />
      <p :if={@help} class="mt-1 text-xs text-gray-500 dark:text-slate-400">
        {@help}
      </p>
      <%= for error <- @errors do %>
        <p class="mt-1 text-xs text-rose-600 dark:text-rose-400">{error}</p>
      <% end %>
      <%= case @status do %>
        <% {:ok, description} -> %>
          <p class="mt-1 text-xs text-teal-600 dark:text-teal-400">
            Valid timeframe · {description}
          </p>
        <% {:error, message} -> %>
          <p class="mt-1 text-xs text-rose-600 dark:text-rose-400">
            {message}
          </p>
        <% _ -> %>
      <% end %>
    </div>
    """
  end
end
