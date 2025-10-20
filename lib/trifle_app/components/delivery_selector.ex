defmodule TrifleApp.Components.DeliverySelector do
  @moduledoc """
  Reusable multi-select input for choosing delivery targets with autocomplete.
  """
  use Phoenix.Component

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, default: nil
  attr :placeholder, :string, default: "Select recipients..."
  attr :options, :list, required: true
  attr :values, :list, default: []
  attr :error, :string, default: nil
  attr :help, :string, default: nil

  def delivery_selector(assigns) do
    assigns =
      assigns
      |> assign_new(:values, fn -> [] end)
      |> assign(:options_json, Jason.encode!(Enum.map(assigns.options, &encode_option/1)))
      |> assign(:selected_json, Jason.encode!(assigns.values || []))
      |> assign(:hidden_value, Enum.join(assigns.values || [], "\n"))

    ~H"""
    <fieldset
      id={@id}
      class="space-y-2"
      x-data="deliverySelector()"
      x-init="init($el)"
      data-options={@options_json}
      data-selected={@selected_json}
    >
      <div class="flex items-center justify-between">
        <%= if @label do %>
          <label for={"#{@id}-input"} class="block text-sm font-medium text-slate-700 dark:text-slate-200">
            {@label}
          </label>
        <% end %>
        <span class="text-xs text-slate-500 dark:text-slate-400" x-show="selected.length > 0" x-text="`${selected.length} selected`"></span>
      </div>

      <div class="flex flex-col gap-2"
        x-on:click.outside="closeDropdown()"
      >
        <input
          x-ref="input"
          x-model="query"
          x-on:input="filter()"
          x-on:focus="openDropdown()"
          x-on:blur="scheduleClose()"
          x-on:keydown.enter.prevent="selectHighlighted()"
          x-on:keydown.arrow-down.prevent="highlightNext()"
          x-on:keydown.arrow-up.prevent="highlightPrev()"
          x-on:keydown.escape.prevent="closeDropdown()"
          id={"#{@id}-input"}
          type="text"
          class={[
            "w-full rounded-lg border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-900 px-3 py-2 text-sm text-slate-900 dark:text-slate-100 placeholder:text-slate-400 focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500",
            @error && "border-rose-500 focus:border-rose-500 focus:ring-rose-500"
          ]}
          autocomplete="off"
          spellcheck="false"
          placeholder={@placeholder}
        />

        <div class="relative">
          <div
            x-show="open && filtered.length > 0"
            x-cloak
            class="absolute left-0 right-0 top-full z-[12060] mt-2 max-h-60 overflow-auto rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 shadow-lg"
            x-on:mousedown="cancelScheduledClose()"
          >
            <ul class="divide-y divide-slate-100 dark:divide-slate-800">
              <template x-for="(option, index) in filtered" x-bind:key="option.handle">
                <li>
                  <button
                    type="button"
                    class="flex w-full flex-col items-start gap-0.5 px-3 py-2 text-left text-sm text-slate-700 dark:text-slate-200 hover:bg-teal-500/10"
                    x-bind:class="index === highlighted ? 'bg-teal-500/10 text-teal-700 dark:text-teal-200' : ''"
                    x-on:mousedown.prevent="select(option.handle)"
                    x-on:click.prevent
                  >
                    <div class="flex items-center gap-2">
                      <span class="text-[0.65rem] font-semibold uppercase tracking-wide text-teal-500 dark:text-teal-300" x-text="option.badge"></span>
                      <span class="font-medium" x-text="option.label"></span>
                    </div>
                    <p class="text-xs text-slate-500 dark:text-slate-400" x-text="option.description"></p>
                  </button>
                </li>
              </template>
            </ul>
          </div>
        </div>

        <div class="flex flex-wrap gap-2 pt-2"
          x-on:mousedown="cancelScheduledClose()"
        >
          <template x-for="item in selectedDetails()" x-bind:key="item.handle">
            <span class="inline-flex items-center gap-1 rounded-full bg-teal-600/10 text-teal-800 dark:text-teal-200 px-2 py-0.5 text-[0.7rem] font-semibold">
              <span class="uppercase text-teal-500 dark:text-teal-300" x-text="item.badge"></span>
              <span x-text="item.label"></span>
              <button
                type="button"
                class="ml-1 inline-flex h-4 w-4 items-center justify-center rounded-full bg-transparent text-slate-500 hover:text-rose-500"
                x-on:click.stop="remove(item.handle)"
              >
                <span class="sr-only">Remove</span>
                &times;
              </button>
            </span>
          </template>
        </div>
      </div>

      <input type="hidden" name={@name} x-ref="hidden" value={@hidden_value} />

      <%= if @help do %>
        <p class="text-xs text-slate-500 dark:text-slate-400">{@help}</p>
      <% end %>

      <%= if @error do %>
        <p class="text-xs font-medium text-rose-600 dark:text-rose-400">{@error}</p>
      <% end %>
    </fieldset>
    """
  end

  defp encode_option(option) do
    %{
      handle: option.handle,
      label: option.label || option.handle,
      description: option.description || "",
      badge: option.badge || badge_from_channel(option.channel),
      search_terms: build_search_terms(option)
    }
  end

  defp badge_from_channel(:email), do: "Email"
  defp badge_from_channel("email"), do: "Email"
  defp badge_from_channel(:slack_webhook), do: "Slack"
  defp badge_from_channel("slack_webhook"), do: "Slack"
  defp badge_from_channel(:webhook), do: "Webhook"
  defp badge_from_channel("webhook"), do: "Webhook"
  defp badge_from_channel(:custom), do: "Custom"
  defp badge_from_channel("custom"), do: "Custom"
  defp badge_from_channel(_), do: "Channel"

  defp build_search_terms(option) do
    [option.handle, option.label, option.description]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end
end
