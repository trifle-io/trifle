defmodule TrifleApp.Components.DashboardWidgets.WidgetEditor do
  @moduledoc false

  use Phoenix.Component

  alias TrifleApp.Components.DashboardWidgets.{
    CategoryEditor,
    DistributionEditor,
    KpiEditor,
    ListEditor,
    TableEditor,
    TextEditor,
    TimeseriesEditor
  }

  attr :widget, :map, required: true
  attr :path_options, :list, default: []

  def editor(assigns) do
    widget = Map.get(assigns, :widget, %{})

    assigns =
      assigns
      |> assign(:widget, widget)
      |> assign_new(:type, fn -> widget_type(widget) end)

    ~H"""
    <%= case @type do %>
      <% "timeseries" -> %>
        <TimeseriesEditor.editor widget={@widget} path_options={@path_options} />
      <% "category" -> %>
        <CategoryEditor.editor widget={@widget} path_options={@path_options} />
      <% "distribution" -> %>
        <DistributionEditor.editor widget={@widget} path_options={@path_options} />
      <% "heatmap" -> %>
        <DistributionEditor.editor widget={@widget} path_options={@path_options} />
      <% "table" -> %>
        <TableEditor.editor widget={@widget} path_options={@path_options} />
      <% "text" -> %>
        <TextEditor.editor widget={@widget} />
      <% "list" -> %>
        <ListEditor.editor widget={@widget} path_options={@path_options} />
      <% _ -> %>
        <KpiEditor.editor widget={@widget} path_options={@path_options} />
    <% end %>
    """
  end

  defp widget_type(widget) do
    widget
    |> Map.get("type", "kpi")
    |> to_string()
    |> String.downcase()
  end
end
