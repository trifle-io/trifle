defmodule TrifleApp.Components.DashboardWidgets.WidgetDataBridge do
  @moduledoc false

  use TrifleApp, :live_component

  alias TrifleApp.Components.DashboardWidgets.{Kpi, Timeseries, Category, Text}

  @impl true
  def update(%{widget: widget} = assigns, socket) do
    widget_id = widget |> Map.get("id") |> to_string()

    widget_type =
      widget
      |> Map.get("type", "kpi")
      |> to_string()
      |> String.downcase()

    payload = compute_payload(widget_type, assigns[:stats], widget)

    socket =
      socket
      |> assign(assigns)
      |> maybe_dispatch(widget_type, widget_id, payload)

    {:ok, socket}
  end

  @impl true
  attr :widget, :map, required: true

  def render(assigns) do
    ~H"""
    <span data-role="widget-data-bridge" data-widget-id={@widget["id"]}></span>
    """
  end

  defp compute_payload("kpi", stats, widget) do
    case Kpi.dataset(stats, widget) do
      nil -> {nil, nil}
      {value, visual} -> {value, visual}
    end
  end

  defp compute_payload("timeseries", stats, widget) do
    Timeseries.dataset(stats, widget)
  end

  defp compute_payload("category", stats, widget) do
    Category.dataset(stats, widget)
  end

  defp compute_payload("text", _stats, widget) do
    Text.widget(widget)
  end

  defp compute_payload(_other, _stats, _widget), do: nil

  defp maybe_dispatch(socket, type, widget_id, payload) do
    case {message_type(type), payload_changed?(socket.assigns[:last_payload], payload)} do
      {nil, _} ->
        socket

      {_type, false} ->
        socket

      {message_type, true} ->
        send(self(), {:widget_data, message_type, widget_id, payload})
        assign(socket, :last_payload, payload)
    end
  end

  defp payload_changed?(previous, current), do: previous != current

  defp message_type("kpi"), do: :kpi
  defp message_type("timeseries"), do: :timeseries
  defp message_type("category"), do: :category
  defp message_type("text"), do: :text
  defp message_type(_other), do: nil
end
