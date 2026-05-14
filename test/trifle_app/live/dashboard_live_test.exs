defmodule TrifleApp.DashboardLiveTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.AccountsFixtures
  alias Trifle.Organizations
  alias Trifle.Organizations.SourceAnnotations
  alias Trifle.Stats.Source
  alias TrifleApp.Components.DashboardWidgets.WidgetView

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})
    app_entitlement_fixture(organization)
    membership = Organizations.get_membership_for_user(user)
    database = database_fixture(%{organization: organization})
    {:ok, _} = Organizations.setup_database(database)

    dashboard_attrs = %{
      "name" => "Widget Workspace Test",
      "key" => "workspace-#{System.unique_integer([:positive])}",
      "database_id" => database.id,
      "source_type" => "database",
      "source_id" => database.id,
      "default_timeframe" => "24h",
      "default_granularity" => "1m",
      "payload" => %{
        "grid" => [
          %{
            "id" => "widget-1",
            "type" => "text",
            "title" => "Original Title",
            "subtype" => "header",
            "payload" => "<h2>Hello</h2>",
            "x" => 0,
            "y" => 0,
            "w" => 4,
            "h" => 2
          }
        ]
      }
    }

    {:ok, dashboard} =
      Organizations.create_dashboard_for_membership(user, membership, dashboard_attrs)

    {:ok,
     conn: log_in_user(conn, user),
     user: user,
     database: database,
     dashboard: dashboard,
     membership: membership}
  end

  test "renders a warning instead of crashing when the source has been removed", %{
    conn: conn,
    dashboard: dashboard,
    database: database
  } do
    assert {:ok, _deleted_database} = Organizations.delete_database(database)

    {:ok, view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    assert html =~ "Source not configured"
    refute has_element?(view, "#dashboard_filter_bar")
  end

  test "renders the shared filter bar without the old content overlay shell", %{
    conn: conn,
    dashboard: dashboard
  } do
    {:ok, view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    assert has_element?(view, "#smart_timeframe")
    refute html =~ "top: 33%;"
  end

  test "renders the full dashboard path in the page heading", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, parent_group} =
      Organizations.create_dashboard_group_for_membership(membership, %{name: "Revenue"})

    {:ok, child_group} =
      Organizations.create_dashboard_group_for_membership(membership, %{
        name: "Quarterly",
        parent_group_id: parent_group.id
      })

    {:ok, dashboard} =
      Organizations.update_dashboard_for_membership(dashboard, membership, %{
        group_id: child_group.id
      })

    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")
    separator = <<194, 183>>

    assert has_element?(
             view,
             "h1",
             "Dashboards #{separator} Quarterly #{separator} Revenue #{separator} Widget Workspace Test"
           )
  end

  test "renders the dashboard footer with mobile collapse controls", %{
    conn: conn,
    dashboard: dashboard
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    assert has_element?(view, "[data-dashboard-footer][data-expanded=\"false\"]")
    assert has_element?(view, "button[aria-controls=\"dashboard-download-menu-summary-details\"]")

    assert has_element?(
             view,
             "#dashboard-download-menu-summary-details[data-dashboard-footer-details]"
           )
  end

  test "authenticated dashboards expose annotation payloads and handle CRUD events", %{
    conn: conn,
    dashboard: dashboard,
    database: database,
    membership: membership
  } do
    source = Source.from_database(database)

    at =
      DateTime.utc_now()
      |> DateTime.add(-3600, :second)
      |> DateTime.truncate(:second)

    at_iso = DateTime.to_iso8601(at)

    {:ok, existing} =
      SourceAnnotations.create_for_source(membership, source, %{
        "at" => at_iso,
        "body" => "Existing annotation"
      })

    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    assert render(view) =~ "DashboardAnnotationsData"

    render_hook(view, "open_annotation_editor", %{"at" => at_iso})
    assert has_element?(view, "#annotation-editor-modal", "Rounded to 1m")

    create_html =
      view
      |> form("#annotation-editor-form", %{
        "annotation" => %{"body" => "Release started"}
      })
      |> render_submit()

    assert create_html =~ "Annotation created successfully"

    annotations =
      SourceAnnotations.list_for_source(
        membership,
        source,
        DateTime.add(at, -3600, :second),
        DateTime.add(at, 3600, :second),
        "1m"
      )

    assert Enum.any?(annotations, &(&1.body == "Release started"))

    group =
      membership
      |> SourceAnnotations.grouped_for_source(
        source,
        DateTime.add(at, -3600, :second),
        DateTime.add(at, 3600, :second),
        "1m"
      )
      |> Enum.find(fn group ->
        Enum.any?(group.annotations, &(&1.id == existing.id))
      end)

    render_hook(view, "open_annotation_group", %{"id" => group.id})
    assert has_element?(view, "#annotation-group-modal", "Existing annotation")

    html =
      render_submit(view, "update_annotation", %{
        "annotation" => %{
          "id" => existing.id,
          "group_id" => group.id,
          "body" => "Updated annotation"
        }
      })

    assert SourceAnnotations.get_annotation(membership, existing.id).body == "Updated annotation"
    assert html =~ "Annotation updated successfully"
    refute has_element?(view, "#annotation-group-modal")

    delete_html =
      render_click(view, "delete_annotation", %{"id" => existing.id, "group_id" => group.id})

    assert delete_html =~ "Annotation deleted successfully"
    assert SourceAnnotations.get_annotation(membership, existing.id) == nil
  end

  test "public dashboards omit annotation payloads", %{
    conn: conn,
    dashboard: dashboard,
    database: database,
    membership: membership
  } do
    source = Source.from_database(database)

    {:ok, _annotation} =
      SourceAnnotations.create_for_source(membership, source, %{
        "at" => DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_iso8601(),
        "body" => "Private annotation"
      })

    {:ok, dashboard} = Organizations.generate_dashboard_public_token(dashboard)

    {:ok, _view, html} = live(conn, ~p"/d/#{dashboard.id}?token=#{dashboard.access_token}")

    assert html =~ "DashboardAnnotationsData"
    refute html =~ "Private annotation"
  end

  test "opens workspace in edit mode and supports tab toggling", %{
    conn: conn,
    dashboard: dashboard
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    refute has_element?(view, "#widget-workspace-modal")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})
    assert has_element?(view, "#widget-workspace-modal")
    assert has_element?(view, "#widget-workspace-modal button[phx-value-tab=\"edit\"]")

    render_click(view, "set_widget_workspace_tab", %{"tab" => "summary"})
    assert has_element?(view, "#widget-workspace-modal button[phx-value-tab=\"summary\"]")
  end

  test "shows discard confirmation for unsaved changes and can cancel/confirm close", %{
    conn: conn,
    dashboard: dashboard
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})

    render_change(view, "widget_editor_change", %{
      "widget_id" => "widget-1",
      "widget_type" => "text",
      "widget_title" => "Updated Title",
      "text_subtype" => "header",
      "text_payload" => "<h2>Hello</h2>"
    })

    render_click(view, "request_close_widget_workspace", %{})

    assert has_element?(
             view,
             "#widget-workspace-modal",
             "You have unsaved changes. Discard them and close?"
           )

    render_click(view, "cancel_close_widget_workspace", %{})
    assert has_element?(view, "#widget-workspace-modal")

    render_click(view, "confirm_close_widget_workspace", %{})
    refute has_element?(view, "#widget-workspace-modal")
  end

  test "updates workspace preview title immediately while editing", %{
    conn: conn,
    dashboard: dashboard
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})

    render_change(view, "widget_editor_change", %{
      "widget_id" => "widget-1",
      "widget_type" => "text",
      "widget_title" => "Live Preview Title",
      "text_subtype" => "header",
      "text_payload" => "<h2>Hello</h2>"
    })

    assert has_element?(view, "#widget-workspace-modal", "Live Preview Title")
  end

  test "workspace title input uses the same dark surface as the rest of the editor", %{
    conn: conn,
    dashboard: dashboard
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})

    assert Regex.match?(~r/id="widget_title".*dark:bg-slate-800/s, render(view))
  end

  test "text widgets preview and save a background selector", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})

    render_change(view, "widget_editor_change", %{
      "widget_id" => "widget-1",
      "widget_type" => "text",
      "widget_title" => "Original Title",
      "text_subtype" => "header",
      "text_background_color_selector" => "warm.3"
    })

    assert render(view) =~ "background-color: #F59E0B"

    render_submit(view, "save_widget", %{
      "widget_id" => "widget-1",
      "widget_type" => "text",
      "widget_title" => "Original Title",
      "text_subtype" => "header",
      "text_background_color_selector" => "warm.3"
    })

    updated = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    [widget] = updated.payload["grid"]

    assert widget["background_color_selector"] == "warm.3"
    refute Map.has_key?(widget, "color")
  end

  test "saves metric widgets with series rows and drops legacy path fields", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})

    render_submit(view, "save_widget", %{
      "widget_id" => "widget-1",
      "widget_type" => "kpi",
      "widget_title" => "Derived KPI",
      "kpi_subtype" => "number",
      "kpi_function" => "mean",
      "kpi_size" => "m",
      "kpi_unit" => "minutes",
      "widget_series_kind" => %{"0" => "path", "1" => "path", "2" => "expression"},
      "widget_series_path" => %{
        "0" => "metrics.sum",
        "1" => "metrics.count",
        "2" => ""
      },
      "widget_series_expression" => %{
        "0" => "",
        "1" => "",
        "2" => "a / b"
      },
      "widget_series_label" => %{
        "0" => "",
        "1" => "",
        "2" => "Average"
      },
      "widget_series_visible" => %{
        "0" => "false",
        "1" => "false",
        "2" => "true"
      },
      "widget_series_color_selector" => %{
        "0" => "default.*",
        "1" => "default.*",
        "2" => "warm.4"
      }
    })

    updated = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    [widget] = updated.payload["grid"]

    assert widget["type"] == "kpi"
    assert widget["title"] == "Derived KPI"
    assert widget["unit"] == "minutes"
    refute Map.has_key?(widget, "path")
    refute Map.has_key?(widget, "paths")
    refute Map.has_key?(widget, "path_inputs")
    refute Map.has_key?(widget, "series_color_selectors")

    assert widget["series"] == [
             %{
               "kind" => "path",
               "path" => "metrics.sum",
               "expression" => "",
               "label" => "",
               "visible" => false,
               "color_selector" => "default.*"
             },
             %{
               "kind" => "path",
               "path" => "metrics.count",
               "expression" => "",
               "label" => "",
               "visible" => false,
               "color_selector" => "default.*"
             },
             %{
               "kind" => "expression",
               "path" => "",
               "expression" => "a / b",
               "label" => "Average",
               "visible" => true,
               "color_selector" => "warm.4"
             }
           ]
  end

  test "legacy metric widgets open through series rows and resave in the new shape", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, dashboard} =
      Organizations.update_dashboard_for_membership(dashboard, membership, %{
        payload: %{
          "grid" => [
            %{
              "id" => "widget-1",
              "type" => "timeseries",
              "title" => "Legacy Series",
              "paths" => ["metrics.count"],
              "series_color_selectors" => %{"metrics.count" => "default.3"},
              "chart_type" => "line",
              "x" => 0,
              "y" => 0,
              "w" => 4,
              "h" => 2
            }
          ]
        }
      })

    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})

    assert has_element?(
             view,
             ~s/input[name="widget_series_path[0]"][value="metrics.count"]/
           )

    render_submit(view, "save_widget", %{
      "widget_id" => "widget-1",
      "widget_type" => "timeseries",
      "widget_title" => "Legacy Series",
      "ts_chart_type" => "line",
      "widget_series_kind" => %{"0" => "path"},
      "widget_series_path" => %{"0" => "metrics.count"},
      "widget_series_expression" => %{"0" => ""},
      "widget_series_label" => %{"0" => ""},
      "widget_series_visible" => %{"0" => "true"},
      "widget_series_color_selector" => %{"0" => "default.3"}
    })

    updated = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    [widget] = updated.payload["grid"]

    assert widget["type"] == "timeseries"
    refute Map.has_key?(widget, "path")
    refute Map.has_key?(widget, "paths")
    refute Map.has_key?(widget, "path_inputs")
    refute Map.has_key?(widget, "series_color_selectors")

    assert widget["series"] == [
             %{
               "kind" => "path",
               "path" => "metrics.count",
               "expression" => "",
               "label" => "",
               "visible" => true,
               "color_selector" => "default.3"
             }
           ]
  end

  test "stale layout updates do not revert a saved widget type", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, dashboard} =
      Organizations.update_dashboard_for_membership(dashboard, membership, %{
        payload: %{
          "grid" => [
            %{
              "id" => "widget-1",
              "type" => "kpi",
              "title" => "Original KPI",
              "function" => "mean",
              "size" => "m",
              "subtype" => "number",
              "series" => [
                %{
                  "kind" => "path",
                  "path" => "metrics.count",
                  "expression" => "",
                  "label" => "",
                  "visible" => true,
                  "color_selector" => "default.*"
                }
              ],
              "x" => 0,
              "y" => 0,
              "w" => 4,
              "h" => 2
            }
          ]
        }
      })

    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})

    render_submit(view, "save_widget", %{
      "widget_id" => "widget-1",
      "widget_type" => "timeseries",
      "widget_title" => "Request Rate",
      "ts_chart_type" => "bar",
      "widget_series_kind" => %{"0" => "path"},
      "widget_series_path" => %{"0" => "metrics.count"},
      "widget_series_expression" => %{"0" => ""},
      "widget_series_label" => %{"0" => ""},
      "widget_series_visible" => %{"0" => "true"},
      "widget_series_color_selector" => %{"0" => "default.3"}
    })

    assert_push_event(view, "dashboard_grid_widget_updated", %{
      id: "widget-1",
      title: "Request Rate",
      type: "timeseries"
    })

    updated = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    [widget] = updated.payload["grid"]

    assert widget["type"] == "timeseries"
    assert widget["title"] == "Request Rate"

    render_hook(view, "dashboard_grid_changed", %{
      "items" => [
        %{
          "id" => "widget-1",
          "title" => "Original KPI",
          "type" => "kpi",
          "x" => 0,
          "y" => 0,
          "w" => 4,
          "h" => 2
        }
      ]
    })

    updated_after_layout = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    [widget_after_layout] = updated_after_layout.payload["grid"]

    assert widget_after_layout["type"] == "timeseries"
    assert widget_after_layout["title"] == "Request Rate"
    assert widget_after_layout["chart_type"] == "bar"
  end

  test "widget series row updates rerender the edit form immediately", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, dashboard} =
      Organizations.update_dashboard_for_membership(dashboard, membership, %{
        payload: %{
          "grid" => [
            %{
              "id" => "widget-1",
              "type" => "timeseries",
              "title" => "Live Series",
              "series" => [
                %{
                  "kind" => "path",
                  "path" => "latency.*.2000+",
                  "expression" => "",
                  "label" => "",
                  "visible" => true,
                  "color_selector" => "purple.*"
                }
              ],
              "chart_type" => "line",
              "x" => 0,
              "y" => 0,
              "w" => 4,
              "h" => 2
            }
          ]
        }
      })

    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})

    refute has_element?(view, ~s(input[name="widget_series_path[1]"]))

    render_hook(view, "widget_series_rows_update", %{
      "widget_id" => "widget-1",
      "rows" => [
        %{
          "kind" => "path",
          "path" => "latency.*.2000+",
          "expression" => "",
          "label" => "",
          "visible" => true,
          "color_selector" => "purple.*"
        },
        %{
          "kind" => "expression",
          "path" => "",
          "expression" => "a / 1000",
          "label" => "Seconds",
          "visible" => true,
          "color_selector" => "default.*"
        }
      ]
    })

    assert has_element?(view, ~s(input[name="widget_series_expression[1]"][value="a / 1000"]))
    assert has_element?(view, ~s(input[name="widget_series_label[1]"][value="Seconds"]))
    assert has_element?(view, ~s(input[name="widget_series_path[1]"][value=""]))

    assert has_element?(
             view,
             ~s(input[name="widget_series_kind[1]"][value="expression"][checked])
           )
  end

  test "widget series row updates preserve blank draft rows in the editor", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, dashboard} =
      Organizations.update_dashboard_for_membership(dashboard, membership, %{
        payload: %{
          "grid" => [
            %{
              "id" => "widget-1",
              "type" => "timeseries",
              "title" => "Blank Draft Row",
              "series" => [
                %{
                  "kind" => "path",
                  "path" => "latency.*.2000+",
                  "expression" => "",
                  "label" => "",
                  "visible" => true,
                  "color_selector" => "purple.*"
                }
              ],
              "chart_type" => "line",
              "x" => 0,
              "y" => 0,
              "w" => 4,
              "h" => 2
            }
          ]
        }
      })

    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})

    render_hook(view, "widget_series_rows_update", %{
      "widget_id" => "widget-1",
      "rows" => [
        %{
          "kind" => "path",
          "path" => "latency.*.2000+",
          "expression" => "",
          "label" => "",
          "visible" => true,
          "color_selector" => "purple.*"
        },
        %{
          "kind" => "expression",
          "path" => "",
          "expression" => "",
          "label" => "",
          "visible" => true,
          "color_selector" => "default.*"
        }
      ]
    })

    assert has_element?(view, ~s([data-series-row][data-index="1"]))
    assert has_element?(view, ~s(input[name="widget_series_expression[1]"][value=""]))

    assert has_element?(
             view,
             ~s(input[name="widget_series_kind[1]"][value="expression"][checked])
           )
  end

  test "widget editor change does not duplicate series rows", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, dashboard} =
      Organizations.update_dashboard_for_membership(dashboard, membership, %{
        payload: %{
          "grid" => [
            %{
              "id" => "widget-1",
              "type" => "timeseries",
              "title" => "No Dupes",
              "series" => [
                %{
                  "kind" => "path",
                  "path" => "latency.*.2000+",
                  "expression" => "",
                  "label" => "",
                  "visible" => true,
                  "color_selector" => "purple.*"
                }
              ],
              "chart_type" => "line",
              "x" => 0,
              "y" => 0,
              "w" => 4,
              "h" => 2
            }
          ]
        }
      })

    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})

    render_hook(view, "widget_series_rows_update", %{
      "widget_id" => "widget-1",
      "rows" => [
        %{
          "kind" => "path",
          "path" => "latency.*.2000+",
          "expression" => "",
          "label" => "",
          "visible" => true,
          "color_selector" => "purple.*"
        },
        %{
          "kind" => "expression",
          "path" => "",
          "expression" => "a / 1000",
          "label" => "Seconds",
          "visible" => true,
          "color_selector" => "default.*"
        }
      ]
    })

    render_change(view, "widget_editor_change", %{
      "widget_id" => "widget-1",
      "widget_type" => "timeseries",
      "widget_title" => "No Dupes",
      "ts_chart_type" => "line",
      "widget_series_kind" => %{"0" => "path", "1" => "expression"},
      "widget_series_path" => %{"0" => "latency.*.2000+", "1" => ""},
      "widget_series_expression" => %{"0" => "", "1" => "a / 1000"},
      "widget_series_label" => %{"0" => "", "1" => "Second"},
      "widget_series_visible" => %{"0" => "true", "1" => "true"},
      "widget_series_color_selector" => %{"0" => "purple.*", "1" => "default.*"}
    })

    assert has_element?(view, ~s([data-series-row][data-index="0"]))
    assert has_element?(view, ~s([data-series-row][data-index="1"]))
    refute has_element?(view, ~s([data-series-row][data-index="2"]))
  end

  test "widget view preserves root groups while flattening widgets for datasets", %{
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, dashboard} =
      Organizations.update_dashboard_for_membership(dashboard, membership, %{
        payload: %{
          "grid" => [
            %{
              "id" => "group-1",
              "type" => "group",
              "title" => "Column A",
              "x" => 0,
              "y" => 0,
              "w" => 6,
              "h" => 5,
              "children" => [
                %{
                  "id" => "widget-1",
                  "type" => "text",
                  "title" => "Grouped Widget",
                  "subtype" => "header",
                  "payload" => "<h2>Hello</h2>",
                  "x" => 0,
                  "y" => 0,
                  "w" => 4,
                  "h" => 2
                }
              ]
            },
            %{
              "id" => "widget-2",
              "type" => "text",
              "title" => "Root Widget",
              "subtype" => "header",
              "payload" => "<h2>World</h2>",
              "x" => 6,
              "y" => 0,
              "w" => 4,
              "h" => 2
            }
          ]
        }
      })

    assert Enum.map(WidgetView.root_grid_items(dashboard), & &1["id"]) == ["group-1", "widget-2"]
    assert Enum.map(WidgetView.grid_items(dashboard), & &1["id"]) == ["widget-1", "widget-2"]
  end

  test "group widgets open in edit mode only and save title changes", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, dashboard} =
      Organizations.update_dashboard_for_membership(dashboard, membership, %{
        payload: %{
          "grid" => [
            %{
              "id" => "group-1",
              "type" => "group",
              "title" => "Original Group",
              "x" => 0,
              "y" => 0,
              "w" => 6,
              "h" => 5,
              "children" => [
                %{
                  "id" => "widget-1",
                  "type" => "text",
                  "title" => "Grouped Widget",
                  "subtype" => "header",
                  "payload" => "<h2>Hello</h2>",
                  "x" => 0,
                  "y" => 0,
                  "w" => 4,
                  "h" => 2
                }
              ]
            }
          ]
        }
      })

    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "open_widget_editor", %{"id" => "group-1"})

    assert has_element?(view, "#widget-workspace-modal", "Widget Group")
    assert has_element?(view, "#widget-workspace-modal button[phx-value-tab=\"edit\"]")
    refute has_element?(view, "#widget-workspace-modal button[phx-value-tab=\"summary\"]")

    render_submit(view, "save_widget", %{
      "widget_id" => "group-1",
      "widget_type" => "group",
      "widget_title" => "Latency Group",
      "group_header_color_selector" => "cool.4"
    })

    assert_push_event(view, "dashboard_grid_widget_updated", %{
      id: "group-1",
      title: "Latency Group",
      type: "group",
      group_header_style: %{
        background: "#0EA5E9",
        border: "rgba(15,23,42,0.08)",
        default: false,
        text: "#0F172A"
      }
    })

    updated = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    [group] = updated.payload["grid"]

    assert group["type"] == "group"
    assert group["title"] == "Latency Group"
    assert group["header_color_selector"] == "cool.4"
    assert [%{"id" => "widget-1"}] = group["children"]

    html =
      render_component(&WidgetView.group_item/1,
        group: group,
        dashboard: updated,
        grid_dom_id: "dashboard-grid",
        editable: true
      )

    assert html =~ "grid-widget-title"
    assert html =~ ~s(data-original-title="Latency Group")
    assert html =~ "background-color: #0EA5E9"

    render_hook(view, "dashboard_grid_changed", %{
      "items" => [
        %{
          "id" => "group-1",
          "type" => "group",
          "title" => "Latency Group",
          "x" => 0,
          "y" => 0,
          "w" => 6,
          "h" => 5,
          "children" => [
            %{
              "id" => "widget-1",
              "title" => "Grouped Widget",
              "x" => 0,
              "y" => 0,
              "w" => 4,
              "h" => 2
            }
          ]
        }
      ]
    })

    updated_after_layout = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    [group_after_layout] = updated_after_layout.payload["grid"]

    assert group_after_layout["title"] == "Latency Group"
    assert group_after_layout["header_color_selector"] == "cool.4"
  end

  test "moving a widget into a group preserves its original type and payload", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, dashboard} =
      Organizations.update_dashboard_for_membership(dashboard, membership, %{
        payload: %{
          "grid" => [
            %{
              "id" => "widget-1",
              "type" => "text",
              "title" => "Original Title",
              "subtype" => "header",
              "payload" => "<h2>Hello</h2>",
              "x" => 0,
              "y" => 0,
              "w" => 4,
              "h" => 2
            },
            %{
              "id" => "group-1",
              "type" => "group",
              "title" => "Column A",
              "x" => 4,
              "y" => 0,
              "w" => 4,
              "h" => 3,
              "children" => []
            }
          ]
        }
      })

    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_hook(view, "dashboard_grid_changed", %{
      "items" => [
        %{
          "id" => "group-1",
          "type" => "group",
          "title" => "Column A",
          "x" => 4,
          "y" => 0,
          "w" => 4,
          "h" => 3,
          "children" => [
            %{
              "id" => "widget-1",
              "title" => "Original Title",
              "x" => 0,
              "y" => 0,
              "w" => 4,
              "h" => 2
            }
          ]
        }
      ]
    })

    updated = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    [%{"id" => "group-1", "children" => [child]}] = updated.payload["grid"]

    assert child["id"] == "widget-1"
    assert child["type"] == "text"
    assert child["title"] == "Original Title"
    assert child["subtype"] == "header"
    assert child["payload"] == "<h2>Hello</h2>"
  end

  test "group layout updates can recover from a stale default widget type", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, dashboard} =
      Organizations.update_dashboard_for_membership(dashboard, membership, %{
        payload: %{
          "grid" => [
            %{
              "id" => "group-1",
              "type" => "kpi",
              "title" => "",
              "series" => [],
              "x" => 0,
              "y" => 0,
              "w" => 6,
              "h" => 4
            }
          ]
        }
      })

    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_hook(view, "dashboard_grid_changed", %{
      "items" => [
        %{
          "id" => "group-1",
          "type" => "group",
          "title" => "Recovered Group",
          "x" => 0,
          "y" => 0,
          "w" => 6,
          "h" => 4,
          "children" => []
        }
      ]
    })

    updated = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    [group] = updated.payload["grid"]

    assert group["type"] == "group"
    assert group["children"] == []
  end

  test "duplicating a widget preserves config, assigns a new id, and appends it to the bottom", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "duplicate_widget", %{"id" => "widget-1"})

    updated = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    [original, duplicate] = updated.payload["grid"]

    assert original["id"] == "widget-1"
    assert duplicate["id"] != "widget-1"
    assert duplicate["type"] == "text"
    assert duplicate["title"] == "Original Title"
    assert duplicate["subtype"] == "header"
    assert duplicate["payload"] == "<h2>Hello</h2>"
    assert duplicate["x"] == 0
    assert duplicate["y"] == 2
    assert duplicate["w"] == 4
    assert duplicate["h"] == 2
  end

  test "deleting a group moves its widgets back to the root grid", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, dashboard} =
      Organizations.update_dashboard_for_membership(dashboard, membership, %{
        payload: %{
          "grid" => [
            %{
              "id" => "group-1",
              "type" => "group",
              "title" => "Column A",
              "x" => 3,
              "y" => 4,
              "w" => 6,
              "h" => 5,
              "children" => [
                %{
                  "id" => "widget-1",
                  "type" => "text",
                  "title" => "Grouped Widget",
                  "subtype" => "header",
                  "payload" => "<h2>Hello</h2>",
                  "x" => 2,
                  "y" => 1,
                  "w" => 4,
                  "h" => 2
                }
              ]
            }
          ]
        }
      })

    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "delete_widget", %{"id" => "group-1"})

    updated = Organizations.get_dashboard_for_membership!(membership, dashboard.id)

    refute Enum.any?(updated.payload["grid"], &(&1["type"] == "group"))

    assert [
             %{
               "id" => "widget-1",
               "type" => "text",
               "x" => 5,
               "y" => 5
             } = widget
           ] = updated.payload["grid"]

    assert widget["w"] == 4
    assert widget["h"] == 2
  end

  test "timeseries save persists hovered-only tooltip and series ordering options", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})

    render_submit(view, "save_widget", %{
      "widget_id" => "widget-1",
      "widget_type" => "timeseries",
      "widget_title" => "Ordered Series",
      "ts_chart_type" => "line",
      "ts_hovered_only" => "true",
      "series_sort" => "alpha",
      "series_priority" => "2\n10",
      "widget_series_kind" => %{"0" => "path"},
      "widget_series_path" => %{"0" => "metrics.distribution.*"},
      "widget_series_expression" => %{"0" => ""},
      "widget_series_label" => %{"0" => ""},
      "widget_series_visible" => %{"0" => "true"},
      "widget_series_color_selector" => %{"0" => "default.*"}
    })

    updated = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    [widget] = updated.payload["grid"]

    assert widget["type"] == "timeseries"
    assert widget["title"] == "Ordered Series"
    assert widget["hovered_only"] == true
    refute Map.has_key?(widget, "tooltip_split")
    assert widget["series_sort"] == "alpha"
    assert widget["series_priority"] == ["2", "10"]
  end
end
