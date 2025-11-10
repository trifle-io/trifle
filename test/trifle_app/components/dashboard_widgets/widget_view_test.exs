defmodule TrifleApp.Components.DashboardWidgets.WidgetViewTest do
  use ExUnit.Case, async: true

  import Phoenix.Component

  alias TrifleApp.Components.DashboardWidgets.{WidgetData, WidgetView}

  setup do
    grid_items = [
      %{
        "id" => "kpi-1",
        "type" => "kpi",
        "title" => "Orders",
        "path" => "metrics.count",
        "function" => "mean",
        "size" => "m",
        "subtype" => "goal",
        "goal_progress" => true,
        "goal_target" => "32",
        "timeseries" => true,
        "w" => 4,
        "h" => 2,
        "x" => 0,
        "y" => 0
      },
      %{
        "id" => "ts-1",
        "type" => "timeseries",
        "title" => "Orders Over Time",
        "paths" => ["metrics.count"],
        "chart_type" => "line",
        "legend" => true,
        "w" => 8,
        "h" => 4,
        "x" => 0,
        "y" => 2
      },
      %{
        "id" => "cat-1",
        "type" => "category",
        "title" => "Orders by Segment",
        "paths" => ["metrics.category"],
        "chart_type" => "bar",
        "w" => 6,
        "h" => 4,
        "x" => 6,
        "y" => 2
      },
      %{
        "id" => "text-1",
        "type" => "text",
        "title" => "Highlights",
        "subtitle" => "Week in review",
        "alignment" => "left",
        "title_size" => "medium",
        "w" => 6,
        "h" => 2,
        "x" => 6,
        "y" => 0
      }
    ]

    timestamps =
      0..2
      |> Enum.map(fn offset ->
        DateTime.from_naive!(~N[2024-01-01 00:00:00], "Etc/UTC")
        |> DateTime.add(offset * 86_400, :second)
      end)

    values = [
      %{"metrics" => %{"count" => 12, "category" => %{"New" => 7, "Returning" => 5}}},
      %{"metrics" => %{"count" => 16, "category" => %{"New" => 9, "Returning" => 7}}},
      %{"metrics" => %{"count" => 20, "category" => %{"New" => 11, "Returning" => 9}}}
    ]

    series = %Trifle.Stats.Series{series: %{at: timestamps, values: values}}

    dataset_maps =
      series
      |> WidgetData.datasets(grid_items)
      |> WidgetData.dataset_maps()

    assigns = %{
      dashboard: %{id: "dash-123", payload: %{"grid" => grid_items}},
      stats: series,
      print_mode: false,
      current_user: %{id: "user-1"},
      can_edit_dashboard: true,
      is_public_access: false,
      public_token: nil,
      kpi_values: dataset_maps.kpi_values,
      kpi_visuals: dataset_maps.kpi_visuals,
      timeseries: dataset_maps.timeseries,
      category: dataset_maps.category,
      table: dataset_maps.table,
      text_widgets: dataset_maps.text
    }

    %{assigns: assigns, grid_items: grid_items}
  end

  test "renders hidden dataset nodes with encoded payloads", %{assigns: assigns} do
    html = render_to_string(&WidgetView.grid/1, assigns)
    {:ok, document} = Floki.parse_document(html)

    [{"div", kpi_attrs, _}] = Floki.find(document, "#widget-data-kpi-1")

    kpi_payload =
      kpi_attrs
      |> Keyword.fetch!("data-kpi-values")
      |> Jason.decode!()

    assert kpi_payload["id"] == "kpi-1"
    assert is_number(kpi_payload["value"])

    [{"div", text_attrs, _}] = Floki.find(document, "#widget-data-text-1")

    text_payload =
      text_attrs
      |> Keyword.fetch!("data-text")
      |> Jason.decode!()

    assert text_payload["id"] == "text-1"
    assert text_payload["subtype"] == "header"
    assert text_payload["title"] == "Highlights"
  end

  test "exposes grid metadata for GridStack initialisation", %{
    assigns: assigns,
    grid_items: grid_items
  } do
    html = render_to_string(&WidgetView.grid/1, assigns)
    {:ok, document} = Floki.parse_document(html)

    [{"div", grid_attrs, _}] = Floki.find(document, "#dashboard-grid")
    assert Keyword.get(grid_attrs, "phx-update") == "ignore"

    initial_grid =
      grid_attrs
      |> Keyword.fetch!("data-initial-grid")
      |> Jason.decode!()
      |> Enum.map(& &1["id"])
      |> Enum.sort()

    expected_ids =
      grid_items
      |> Enum.map(& &1["id"])
      |> Enum.sort()

    assert initial_grid == expected_ids
  end

  test "renders KPI and text widget chrome server-side", %{assigns: assigns} do
    html = render_to_string(&WidgetView.grid/1, assigns)
    {:ok, document} = Floki.parse_document(html)

    assert [_] = Floki.find(document, "#grid-widget-content-kpi-1 .kpi-wrap")

    [{"div", title_attrs, _}] =
      Floki.find(document, "#grid-widget-content-text-1 .grid-widget-title")

    assert Keyword.get(title_attrs, "aria-hidden") == "true"

    [{"div", body_attrs, _}] =
      Floki.find(document, "#grid-widget-content-text-1 .text-widget-body")

    assert Keyword.get(body_attrs, "data-text-subtype") == "header"

    classes = body_attrs |> Keyword.get("class", "")
    assert String.contains?(classes, "items-start")
    assert String.contains?(classes, "text-widget-body")
  end
end
