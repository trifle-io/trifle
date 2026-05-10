defmodule TrifleApp.Components.DashboardWidgets.GroupExpansionTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Trifle.Stats.Series

  alias TrifleApp.Components.DashboardWidgets.{
    GroupExpansion,
    LayoutTree,
    WidgetData,
    WidgetView
  }

  @endpoint TrifleWeb.Endpoint

  defp stats do
    %Series{
      series: %{
        at: [~U[2026-01-01 00:00:00Z]],
        values: [
          %{
            "jobs" => %{
              "email" => %{"count" => 3, "failed" => 1},
              "sms" => %{"count" => 5}
            },
            "system" => %{"count" => 9}
          }
        ]
      }
    }
  end

  test "regular group path prefixes child path rows and respects absolute paths" do
    [group] =
      [
        %{
          "id" => "group-1",
          "type" => "group",
          "title" => "Email",
          "group_path" => "jobs.email",
          "children" => [
            %{
              "id" => "ts-1",
              "type" => "timeseries",
              "series" => [
                %{"kind" => "path", "path" => "count", "visible" => true},
                %{"kind" => "path", "path" => "$.system.count", "visible" => true}
              ]
            }
          ]
        }
      ]
      |> GroupExpansion.expand_root_items(stats())

    [child] = LayoutTree.group_children(group)

    assert [
             %{"path" => "jobs.email.count"},
             %{"path" => "system.count"}
           ] = Enum.map(child["series"], &Map.take(&1, ["path"]))
  end

  test "terminal wildcard group path expands into concrete groups with synthetic copies" do
    [first, second, widget_after] =
      [
        %{
          "id" => "group-1",
          "type" => "group",
          "title" => "Jobs",
          "group_path" => "jobs.*",
          "x" => 0,
          "y" => 0,
          "w" => 12,
          "h" => 4,
          "children" => [
            %{
              "id" => "ts-1",
              "type" => "timeseries",
              "series" => [%{"kind" => "path", "path" => "count", "visible" => true}]
            }
          ]
        },
        %{"id" => "kpi-after", "type" => "kpi", "x" => 0, "y" => 4, "w" => 3, "h" => 2}
      ]
      |> GroupExpansion.expand_root_items(stats())

    assert first["id"] == "group-1"
    assert first["title"] == "Jobs: jobs.email"
    refute GroupExpansion.derived?(first)

    [first_child] = LayoutTree.group_children(first)
    assert first_child["id"] == "ts-1"

    assert [%{"path" => "jobs.email.count"}] =
             Enum.map(first_child["series"], &Map.take(&1, ["path"]))

    assert GroupExpansion.derived?(second)
    assert second["title"] == "Jobs: jobs.sms"
    assert second["id"] =~ "--expanded--1--jobs-sms"

    [second_child] = LayoutTree.group_children(second)
    assert second_child["id"] =~ second["id"]

    assert [%{"path" => "jobs.sms.count"}] =
             Enum.map(second_child["series"], &Map.take(&1, ["path"]))

    assert widget_after["y"] == 8
  end

  test "invalid middle wildcard group path is ignored" do
    [group] =
      [
        %{
          "id" => "group-1",
          "type" => "group",
          "group_path" => "jobs.*.count",
          "children" => [
            %{
              "id" => "ts-1",
              "type" => "timeseries",
              "series" => [%{"kind" => "path", "path" => "count", "visible" => true}]
            }
          ]
        }
      ]
      |> GroupExpansion.expand_root_items(stats())

    [child] = LayoutTree.group_children(group)
    assert [%{"path" => "count"}] = Enum.map(child["series"], &Map.take(&1, ["path"]))
  end

  test "expanded groups carry rotated header style payload for client-created copies" do
    [first, second] =
      [
        %{
          "id" => "group-1",
          "type" => "group",
          "title" => "Jobs",
          "group_path" => "jobs.*",
          "header_color_selector" => "warm.*",
          "children" => []
        }
      ]
      |> GroupExpansion.expand_root_items(stats())

    assert first["_group_header_style"]["background"] == "#FDE68A"
    assert second["_group_header_style"]["background"] == "#FCD34D"

    [persisted] = GroupExpansion.persisted_items([first])
    refute Map.has_key?(persisted, "_group_header_style")
  end

  test "widget datasets are built for expanded child widget ids" do
    dashboard = %{
      id: "dash-1",
      payload: %{
        "grid" => [
          %{
            "id" => "group-1",
            "type" => "group",
            "title" => "Jobs",
            "group_path" => "jobs.*",
            "children" => [
              %{
                "id" => "ts-1",
                "type" => "timeseries",
                "series" => [%{"kind" => "path", "path" => "count", "visible" => true}]
              }
            ]
          }
        ]
      }
    }

    dataset_maps =
      stats()
      |> WidgetData.datasets_from_dashboard(dashboard)
      |> WidgetData.dataset_maps()

    assert %{"ts-1" => %{series: [%{source_path: "jobs.email.count"}]}} =
             dataset_maps.timeseries

    assert %{
             "group-1--expanded--1--jobs-sms--ts-1" => %{
               series: [%{source_path: "jobs.sms.count"}]
             }
           } = dataset_maps.timeseries
  end

  test "derived groups render without edit controls and use rotated header colors" do
    group = %{
      "id" => "group-1",
      "type" => "group",
      "title" => "Jobs",
      "group_path" => "jobs.*",
      "header_color_selector" => "warm.*",
      "children" => [
        %{
          "id" => "ts-1",
          "type" => "timeseries",
          "series" => [%{"kind" => "path", "path" => "count", "visible" => true}]
        }
      ]
    }

    html =
      render_component(&WidgetView.grid/1,
        dashboard: %{id: "dash-1", payload: %{"grid" => [group]}},
        stats: stats(),
        current_user: %{id: "user-1"},
        can_edit_dashboard: true,
        kpi_values: %{},
        kpi_visuals: %{},
        timeseries: %{},
        category: %{},
        table: %{},
        text_widgets: %{},
        list: %{},
        distribution: %{}
      )

    {:ok, document} = Floki.parse_document(html)

    [derived] =
      Floki.find(document, ~s(.grid-stack-item[data-derived-group="1"][data-item-kind="group"]))

    {"div", derived_attrs, _} = derived
    derived_id = Map.new(derived_attrs)["gs-id"]

    assert derived_id =~ "--expanded--1--jobs-sms"
    assert Floki.find(derived, ".grid-widget-edit") == []

    first_header_styles =
      document
      |> Floki.find("#dashboard-grid-grid-widget-content-group-1 .grid-widget-header")
      |> Enum.map(fn header -> header |> elem(1) |> Map.new() |> Map.get("style", "") end)

    second_header_styles =
      document
      |> Floki.find("#dashboard-grid-grid-widget-content-#{derived_id} .grid-widget-header")
      |> Enum.map(fn header -> header |> elem(1) |> Map.new() |> Map.get("style", "") end)

    assert Enum.any?(first_header_styles, &String.contains?(&1, "background-color: #FDE68A"))
    assert Enum.any?(second_header_styles, &String.contains?(&1, "background-color: #FCD34D"))
  end
end
