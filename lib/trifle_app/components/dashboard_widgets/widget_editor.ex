defmodule TrifleApp.Components.DashboardWidgets.WidgetEditor do
  @moduledoc false

  use Phoenix.Component

  alias TrifleApp.Components.DashboardWidgets.Registry

  attr :widget, :map, required: true
  attr :path_options, :list, default: []

  def editor(assigns) do
    widget = Map.get(assigns, :widget, %{})

    assigns =
      assigns
      |> assign(:widget, widget)
      |> assign_new(:type, fn -> widget_type(widget) end)
      |> assign(:editor_module, Registry.editor_module(widget_type(widget)))

    ~H"""
    {render_editor_component(@editor_module, @widget, @path_options)}
    """
  end

  defp render_editor_component(nil, _widget, _path_options), do: nil

  defp render_editor_component(editor_module, widget, path_options) do
    editor_module.editor(%{
      widget: widget,
      path_options: path_options,
      __changed__: %{}
    })
  end

  defp widget_type(widget) do
    Registry.widget_type(widget)
  end
end
