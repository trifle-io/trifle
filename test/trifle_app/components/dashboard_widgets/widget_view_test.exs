defmodule TrifleApp.Components.DashboardWidgets.WidgetViewTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  @endpoint TrifleWeb.Endpoint

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
        "id" => "list-1",
        "type" => "list",
        "title" => "Keys",
        "path" => "keys",
        "w" => 4,
        "h" => 3,
        "x" => 0,
        "y" => 4
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
      %{
        "metrics" => %{"count" => 12, "category" => %{"New" => 7, "Returning" => 5}},
        "keys" => %{"alpha" => 4, "beta" => 3}
      },
      %{
        "metrics" => %{"count" => 16, "category" => %{"New" => 9, "Returning" => 7}},
        "keys" => %{"alpha" => 5, "beta" => 2}
      },
      %{
        "metrics" => %{"count" => 20, "category" => %{"New" => 11, "Returning" => 9}},
        "keys" => %{"alpha" => 6, "beta" => 4}
      }
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
      text_widgets: dataset_maps.text,
      list: dataset_maps.list,
      distribution: dataset_maps.distribution
    }

    %{assigns: assigns, grid_items: grid_items}
  end

  test "renders hidden dataset nodes with encoded payloads", %{assigns: assigns} do
    html = render_component(&WidgetView.grid/1, assigns)
    {:ok, document} = Floki.parse_document(html)

    [{"div", kpi_attrs, _}] = Floki.find(document, "#widget-data-kpi-1")

    kpi_payload_envelope =
      kpi_attrs
      |> Map.new()
      |> Map.fetch!("data-widget-payload")
      |> Jason.decode!()

    assert kpi_payload_envelope["id"] == "kpi-1"
    assert kpi_payload_envelope["type"] == "kpi"
    assert is_number(kpi_payload_envelope["payload"]["value"]["value"])

    [{"div", text_attrs, _}] = Floki.find(document, "#widget-data-text-1")

    text_payload_envelope =
      text_attrs
      |> Map.new()
      |> Map.fetch!("data-widget-payload")
      |> Jason.decode!()

    assert text_payload_envelope["id"] == "text-1"
    assert text_payload_envelope["type"] == "text"
    assert text_payload_envelope["payload"]["subtype"] == "header"
    assert text_payload_envelope["payload"]["title"] == "Highlights"
  end

  test "exposes grid metadata for GridStack initialisation", %{
    assigns: assigns,
    grid_items: grid_items
  } do
    html = render_component(&WidgetView.grid/1, assigns)
    {:ok, document} = Floki.parse_document(html)

    [{"div", grid_attrs, _}] = Floki.find(document, "#dashboard-grid")
    assert grid_attrs |> Map.new() |> Map.get("phx-update") == "ignore"

    initial_grid =
      grid_attrs
      |> Map.new()
      |> Map.fetch!("data-initial-grid")
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
    html = render_component(&WidgetView.grid/1, assigns)
    {:ok, document} = Floki.parse_document(html)

    assert [_] = Floki.find(document, "#grid-widget-content-kpi-1 .kpi-wrap")

    [{"div", title_attrs, _}] =
      Floki.find(document, "#grid-widget-content-text-1 .grid-widget-title")

    assert title_attrs |> Map.new() |> Map.get("aria-hidden") == "true"

    [{"div", body_attrs, _}] =
      Floki.find(document, "#grid-widget-content-text-1 .text-widget-body")

    assert body_attrs |> Map.new() |> Map.get("data-text-subtype") == "header"

    classes = body_attrs |> Map.new() |> Map.get("class", "")
    assert String.contains?(classes, "items-start")
    assert String.contains?(classes, "text-widget-body")
  end

  test "renders list widget entries", %{assigns: assigns} do
    html = render_component(&WidgetView.grid/1, assigns)
    {:ok, document} = Floki.parse_document(html)

    badges = Floki.find(document, "#grid-widget-content-list-1 li span.inline-flex.items-center")
    assert length(badges) > 0

    labels =
      document
      |> Floki.find("#grid-widget-content-list-1 .font-mono")
      |> Enum.map(fn {"span", _attrs, [text]} -> String.trim(text) end)

    assert "alpha" in labels
  end
end
