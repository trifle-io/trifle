defmodule TrifleApp.Components.DashboardWidgets.Text do
  @moduledoc false

  alias TrifleApp.Components.DashboardWidgets.Helpers, as: WidgetHelpers

  @spec widgets(list() | nil) :: list()
  def widgets(nil), do: []

  def widgets(grid_items) do
    grid_items
    |> Enum.filter(fn item ->
      String.downcase(to_string(item["type"] || "")) == "text"
    end)
    |> Enum.map(&widget/1)
  end

  @spec widget(map() | nil) :: map() | nil
  def widget(nil), do: nil

  def widget(item) do
    id = to_string(item["id"])
    subtype = WidgetHelpers.normalize_text_subtype(item["subtype"])
    surface = WidgetHelpers.text_widget_surface_colors(item)

    base = %{
      id: id,
      subtype: subtype,
      title: to_string(item["title"] || ""),
      uses_default_background: surface.default?,
      background_color: surface.background,
      text_color: surface.text,
      border_color: surface.border
    }

    case subtype do
      "html" ->
        payload =
          item
          |> Map.get("payload")
          |> WidgetHelpers.sanitize_text_widget_html()

        Map.put(base, :payload, payload)

      _ ->
        base
        |> Map.put(
          :title_size,
          WidgetHelpers.normalize_text_title_size(item["title_size"])
        )
        |> Map.put(
          :alignment,
          WidgetHelpers.normalize_text_alignment(item["alignment"])
        )
        |> Map.put(:subtitle, item["subtitle"] |> to_string() |> String.trim())
    end
  end
end
