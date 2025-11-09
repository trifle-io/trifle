defmodule TrifleApp.Components.PathInput do
  @moduledoc false

  use Phoenix.Component

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, default: ""
  attr :path_options, :list, default: []

  attr :input_class, :string,
    default:
      "block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"

  def path_autocomplete_input(assigns) do
    assigns = assign(assigns, :options_json, Jason.encode!(assigns.path_options))

    ~H"""
    <div id={"#{@id}-wrapper"} class="relative" phx-hook="PathAutocomplete" data-paths={@options_json}>
      <input
        id={@id}
        type="text"
        name={@name}
        value={@value}
        placeholder={@placeholder}
        class={@input_class}
        autocomplete="off"
        spellcheck="false"
        data-role="path-input"
      />
      <div
        id={"#{@id}-suggestions"}
        data-role="suggestions"
        phx-update="ignore"
        class="absolute z-20 mt-1 w-full max-h-60 overflow-y-auto rounded-md border border-gray-200 bg-white shadow-lg dark:border-slate-600 dark:bg-slate-800 hidden"
      >
      </div>
    </div>
    """
  end
end
