defmodule TrifleApp.Components.SegmentFilters do
  @moduledoc "Shared segment controls for dashboard and monitor filter bar attachments."
  use TrifleApp, :html

  attr :id, :string, required: true
  attr :segments, :list, required: true
  attr :values, :map, required: true

  def filters(assigns) do
    ~H"""
    <form
      id={@id}
      aria-label="Segment filters"
      class="flex flex-wrap items-center gap-3"
      phx-change="update_segment_filters"
      phx-submit="update_segment_filters"
    >
      <%= for {segment, index} <- Enum.with_index(@segments) do %>
        <% name = segment["name"] %>
        <% label = segment["label"] || name || "Segment" %>
        <% value = Map.get(@values, name, "") %>
        <%= if segment["type"] == "text" do %>
          <.labeled_input
            id={"#{@id}-#{index}"}
            label={label}
            name={"segments[#{name}]"}
            value={value}
            placeholder={segment["placeholder"] || ""}
            phx-debounce="500"
            class="w-full min-w-0 sm:w-56"
            input_class="h-10 text-sm"
          />
        <% else %>
          <% groups = segment["groups"] || [] %>
          <% has_items = Enum.any?(groups, fn group -> (group["items"] || []) != [] end) %>
          <.labeled_select
            id={"#{@id}-#{index}"}
            label={label}
            name={"segments[#{name}]"}
            class="w-full min-w-0 sm:w-56"
            select_class="h-10 text-sm"
          >
            <%= for group <- groups do %>
              <%= if group["label"] && group["label"] != "" do %>
                <optgroup label={group["label"]}>
                  <.options items={group["items"] || []} value={value} />
                </optgroup>
              <% else %>
                <.options items={group["items"] || []} value={value} />
              <% end %>
            <% end %>
            <option :if={!has_items} value="" selected={value in [nil, ""]} disabled>
              No options configured
            </option>
          </.labeled_select>
        <% end %>
      <% end %>
    </form>
    """
  end

  attr :items, :list, required: true
  attr :value, :string, required: true

  defp options(assigns) do
    ~H"""
    <option
      :for={item <- @items}
      value={item["value"] || ""}
      selected={(item["value"] || "") == @value}
    >
      {item["label"] || item["value"] || ""}
    </option>
    """
  end
end
