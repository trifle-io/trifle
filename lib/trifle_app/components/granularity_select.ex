defmodule TrifleApp.Components.GranularitySelect do
  @moduledoc false

  use Phoenix.Component

  import TrifleApp.CoreComponents, only: [translate_error: 1]

  alias TrifleApp.Granularity

  attr :id, :string
  attr :name, :string
  attr :value, :string, default: ""
  attr :field, Phoenix.HTML.FormField
  attr :label, :string, default: nil
  attr :help, :string, default: nil
  attr :prompt, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :options, :list, default: []
  attr :wrapper_class, :string, default: "grid grid-cols-1 sm:max-w-xs mt-1"

  attr :input_class, :string,
    default:
      "col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"

  def granularity_select(assigns) do
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
            "granularity_select expects either a :field or a :name attribute"
    end

    assigns =
      assigns
      |> assign(:value, assigns.value || "")
      |> assign(:normalized_options, normalize_options(assigns.options))

    ~H"""
    <div>
      <label :if={@label} class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
        {@label}
      </label>
      <div class={@wrapper_class}>
        <select
          id={@id}
          name={@name}
          class={[
            @input_class,
            @disabled &&
              "bg-gray-100 dark:bg-slate-700 text-gray-500 dark:text-slate-400 cursor-not-allowed"
          ]}
          disabled={@disabled || Enum.empty?(@normalized_options)}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          <%= for opt <- @normalized_options do %>
            <option value={opt.value} selected={to_string(opt.value) == to_string(@value)}>
              {opt.label} ({opt.badge})
            </option>
          <% end %>
        </select>
        <svg
          viewBox="0 0 16 16"
          fill="currentColor"
          data-slot="icon"
          aria-hidden="true"
          class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 dark:text-slate-400 sm:h-4 sm:w-4"
        >
          <path
            d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z"
            clip-rule="evenodd"
            fill-rule="evenodd"
          />
        </svg>
      </div>
      <p :if={@help} class="mt-1 text-xs text-gray-500 dark:text-slate-400">
        {@help}
      </p>
      <%= for error <- @errors do %>
        <p class="mt-1 text-xs text-rose-600 dark:text-rose-400">{error}</p>
      <% end %>
    </div>
    """
  end

  defp normalize_options(options) do
    options
    |> List.wrap()
    |> Enum.flat_map(fn
      %{value: value, label: label} = opt ->
        [
          %{
            value: to_string(value),
            label: label || Granularity.display_name(value),
            badge: opt[:badge] || to_string(value)
          }
        ]

      value when is_binary(value) or is_atom(value) ->
        Granularity.options([value])

      _ ->
        []
    end)
  end
end
