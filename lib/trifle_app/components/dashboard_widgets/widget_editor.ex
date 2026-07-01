defmodule TrifleApp.Components.DashboardWidgets.WidgetEditor do
  @moduledoc false

  use Phoenix.Component

  alias TrifleApp.Components.DashboardWidgets.Registry

  attr :widget, :map, required: true
  attr :path_options, :list, default: []
  attr :group_path, :string, default: nil

  def editor(assigns) do
    widget = Map.get(assigns, :widget, %{})

    assigns =
      assigns
      |> assign(:widget, widget)
      |> assign_new(:type, fn -> widget_type(widget) end)
      |> assign(:editor_module, Registry.editor_module(widget_type(widget)))

    ~H"""
    {render_editor_component(@editor_module, @widget, @path_options, @group_path)}
    """
  end

  defp render_editor_component(nil, _widget, _path_options, _group_path), do: nil

  defp render_editor_component(editor_module, widget, path_options, group_path) do
    editor_module.editor(%{
      widget: widget,
      path_options: path_options,
      group_path: group_path,
      __changed__: %{widget: true, path_options: true, group_path: true}
    })
  end

  defp widget_type(widget) do
    Registry.widget_type(widget)
  end
end
