defmodule TrifleApp.DashboardLiveTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.AccountsFixtures
  alias Trifle.Organizations
  alias Trifle.Organizations.SourceAnnotations
  alias Trifle.Repo
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

  test "system templates keep dashboard configuration available but disable layout editing", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    assert {:ok, dashboard} =
             Organizations.link_dashboard_template(dashboard, membership, "system:blank")

    {:ok, view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    refute has_element?(view, "#dashboard-#{dashboard.id}-add-widget")
    assert html =~ "Configure"

    render_hook(view, "dashboard_grid_changed", %{
      "items" => [%{"id" => "blocked", "x" => 0, "y" => 0, "w" => 2, "h" => 2}]
    })

    reloaded = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    assert reloaded.payload == %{"grid" => []}
  end

  test "configure groups templates and switches the selected layout immediately", %{
    conn: conn,
    user: user,
    dashboard: dashboard,
    membership: membership
  } do
    template_payload = %{"grid" => [%{"id" => "shared-widget", "type" => "text"}]}

    {:ok, template} =
      Organizations.create_dashboard_template(user, membership, %{
        name: "Reusable layout",
        payload: template_payload
      })

    template_id = "user:#{template.id}"
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}/configure")

    assert has_element?(
             view,
             "#dashboard-template-field #configure_template_id[phx-hook='ConfirmSelect'][data-confirm-message][data-current-value='']"
           )

    refute has_element?(view, "#configure_template_id[data-confirm]")

    assert has_element?(
             view,
             "#configure_template_id optgroup[label='System templates'] option[value='system:blank']",
             "Blank dashboard"
           )

    assert has_element?(
             view,
             "#configure_template_id optgroup[label='Organization templates'] option[value='#{template_id}']",
             "Reusable layout"
           )

    html = render_hook(view, "change_dashboard_template", %{"value" => template_id})

    assert html =~ "Dashboard now uses Reusable layout"
    assert_patch(view, ~p"/dashboards/#{dashboard.id}")
    refute has_element?(view, "#configure-modal")

    reloaded = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    assert reloaded.template_id == template_id
    assert reloaded.payload == template_payload
    assert Repo.get!(Trifle.Organizations.Dashboard, dashboard.id).payload == %{}
  end

  test "configure presents dashboard actions in their intended order", %{
    conn: conn,
    dashboard: dashboard
  } do
    {:ok, view, html} = live(conn, ~p"/dashboards/#{dashboard.id}/configure")

    assert has_element?(view, "#dashboard-actions h3", "Actions")

    positions =
      Enum.map(
        [
          "dashboard-action-visibility",
          "dashboard-action-lock",
          "dashboard-action-public-link",
          "dashboard-action-duplicate",
          "dashboard-action-template",
          "dashboard-danger-zone"
        ],
        fn id ->
          {position, _length} = :binary.match(html, ~s(id="#{id}"))
          position
        end
      )

    assert positions == Enum.sort(positions)
  end

  test "configure shows field validation errors when settings cannot be saved", %{
    conn: conn,
    dashboard: dashboard,
    database: database
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}/configure")

    html =
      render_hook(view, "save_settings", %{
        "name" => "",
        "key" => dashboard.key,
        "timeframe" => dashboard.default_timeframe,
        "granularity" => dashboard.default_granularity,
        "source_ref" => "database:#{database.id}"
      })

    assert html =~ "Name can&#39;t be blank"
  end

  test "configure converts a local dashboard to a template and detaches a template snapshot", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    original_payload = dashboard.payload
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}/configure")

    assert has_element?(view, "#convert-dashboard-to-template", "Create template")

    assert has_element?(
             view,
             "#convert-dashboard-to-template svg[data-template-action-icon='copy']"
           )

    refute has_element?(view, "#detach-dashboard-template")

    html =
      render_click(view, "convert_dashboard_to_template", %{
        "name" => "Workspace template"
      })

    assert html =~ "Converted to template Workspace template"
    assert_patch(view, ~p"/dashboards/#{dashboard.id}")
    refute has_element?(view, "#configure-modal")

    template =
      membership
      |> Organizations.list_user_dashboard_templates_for_membership()
      |> Enum.find(&(&1.name == "Workspace template"))

    assert template.payload == original_payload

    converted = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    assert converted.template_id == "user:#{template.id}"

    render_patch(view, ~p"/dashboards/#{dashboard.id}/configure")

    assert has_element?(view, "#detach-dashboard-template", "Detach")

    assert has_element?(
             view,
             "#detach-dashboard-template svg[data-template-action-icon='detach']"
           )

    html = render_click(view, "detach_dashboard_template")

    assert html =~ "Dashboard detached from template"
    assert_patch(view, ~p"/dashboards/#{dashboard.id}")
    refute has_element?(view, "#configure-modal")

    detached = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    assert detached.template_id == nil
    assert detached.payload == original_payload
  end

  test "stale shared template layout edits require a reload", %{
    conn: conn,
    user: user,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, template} =
      Organizations.create_dashboard_template(user, membership, %{
        name: "Shared layout",
        payload: dashboard.payload
      })

    template_id = "user:#{template.id}"
    {:ok, dashboard} = Organizations.link_dashboard_template(dashboard, membership, template_id)
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    external_payload = %{"grid" => [%{"id" => "external", "type" => "text"}]}

    assert {:ok, _template} =
             Organizations.update_dashboard_template(template, user, membership, %{
               payload: external_payload,
               template_version: 1
             })

    html =
      render_hook(view, "dashboard_grid_changed", %{
        "items" => [%{"id" => "stale", "x" => 0, "y" => 0, "w" => 2, "h" => 2}]
      })

    assert html =~ "Reload the page before making more layout changes"

    reloaded = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    assert reloaded.payload == external_payload
    assert reloaded.template_version == 2
  end

  test "duplicating a template-backed dashboard preserves its template reference", %{
    conn: conn,
    user: user,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, template} =
      Organizations.create_dashboard_template(user, membership, %{
        name: "Reusable layout",
        payload: dashboard.payload
      })

    template_id = "user:#{template.id}"
    {:ok, dashboard} = Organizations.link_dashboard_template(dashboard, membership, template_id)
    {:ok, view, _html} = live(conn, ~p"/dashboards")

    render_click(view, "duplicate_dashboard", %{"id" => dashboard.id})

    copy =
      user
      |> Organizations.list_all_dashboards_for_membership(membership)
      |> Enum.find(&(&1.name == "#{dashboard.name} (copy)"))

    assert copy.template_id == template_id
    assert copy.payload == dashboard.payload
    assert Repo.get!(Trifle.Organizations.Dashboard, copy.id).payload == %{}
  end

  test "dashboard list uses native links and exposes group state for preloading", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, group} =
      Organizations.create_dashboard_group_for_membership(membership, %{name: "Revenue"})

    {:ok, dashboard} =
      Organizations.update_dashboard_for_membership(dashboard, membership, %{
        group_id: group.id
      })

    {:ok, view, html} = live(conn, ~p"/dashboards")

    assert has_element?(
             view,
             "a[data-dashboard-row-link][href=\"/dashboards/#{dashboard.id}\"]"
           )

    refute html =~ ~s(phx-click="dashboard_clicked")

    assert has_element?(
             view,
             "#dashboard-root[data-storage-key=\"dashboard_group_collapsed_default\"]"
           )

    assert has_element?(view, "[data-dashboard-group-content=\"#{group.id}\"]")
    assert has_element?(view, "[data-dashboard-group-collapsed-icon=\"#{group.id}\"].hidden")

    assert has_element?(
             view,
             "[data-dashboard-group-expanded-icon=\"#{group.id}\"]:not(.hidden)"
           )

    render_hook(view, "set_collapsed_groups", %{"ids" => [group.id]})

    refute has_element?(view, "[data-dashboard-group-content=\"#{group.id}\"]")

    assert has_element?(
             view,
             "[data-dashboard-group-collapsed-icon=\"#{group.id}\"]:not(.hidden)"
           )

    assert has_element?(view, "[data-dashboard-group-expanded-icon=\"#{group.id}\"].hidden")
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

    assert has_element?(view, "[data-dashboard-footer-shortcuts-trigger]")
    assert has_element?(view, "#keyboard-shortcuts-title", "Keyboard shortcuts")
    assert has_element?(view, "kbd", "Cmd/Ctrl")
    assert has_element?(view, "kbd", "Esc")
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

    html = render_click(view, "open_widget_editor", %{"id" => "widget-1"})
    assert has_element?(view, "#widget-workspace-modal")
    assert has_element?(view, "#widget-workspace-modal button[phx-value-tab=\"edit\"]")
    assert html =~ ~s(phx-hook="DeferredFormInputs")
    assert html =~ ~s(data-deferred-input-debounce="600")

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

  test "child widgets under a group path can save nested series rows", %{
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
              "title" => "Stores",
              "group_path" => "store.*",
              "x" => 0,
              "y" => 0,
              "w" => 6,
              "h" => 5,
              "children" => [
                %{
                  "id" => "widget-1",
                  "type" => "timeseries",
                  "title" => "Store Count",
                  "series" => [
                    %{
                      "kind" => "path",
                      "path" => "count",
                      "expression" => "",
                      "label" => "",
                      "visible" => true,
                      "color_selector" => "default.*"
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
          ]
        }
      })

    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    html = render_click(view, "open_widget_editor", %{"id" => "widget-1"})

    assert has_element?(view, ~s(input[name="widget_series_kind[0]"][value="nested"]))
    assert html =~ ~s(title="Nested: path under group prefix store.*")

    render_hook(view, "widget_series_rows_update", %{
      "widget_id" => "widget-1",
      "rows" => [
        %{
          "kind" => "nested",
          "path" => "count",
          "expression" => "",
          "label" => "Count",
          "visible" => true,
          "color_selector" => "default.*"
        }
      ]
    })

    assert has_element?(
             view,
             ~s(input[name="widget_series_kind[0]"][value="nested"][checked])
           )

    render_submit(view, "save_widget", %{
      "widget_id" => "widget-1",
      "widget_type" => "timeseries",
      "widget_title" => "Store Count",
      "ts_chart_type" => "line",
      "widget_series_kind" => %{"0" => "nested"},
      "widget_series_path" => %{"0" => "count"},
      "widget_series_expression" => %{"0" => ""},
      "widget_series_label" => %{"0" => "Count"},
      "widget_series_visible" => %{"0" => "true"},
      "widget_series_color_selector" => %{"0" => "default.*"}
    })

    updated = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    [%{"children" => [child]}] = updated.payload["grid"]

    assert [%{"kind" => "nested", "path" => "count", "label" => "Count"}] =
             Enum.map(child["series"], &Map.take(&1, ["kind", "path", "label"]))
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
      "series_aliases" => ~s({"2": "Two", "10": "Ten"}),
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
    assert widget["series_aliases"] == %{"2" => "Two", "10" => "Ten"}
  end

  test "timeseries save accepts visual aliases and priority rows", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})

    render_submit(view, "save_widget", %{
      "widget_id" => "widget-1",
      "widget_type" => "timeseries",
      "widget_title" => "Visual Ordered Series",
      "ts_chart_type" => "line",
      "series_display_mode" => "visual",
      "series_sort" => "natural",
      "series_alias_key" => %{
        "0" => " seller1 ",
        "1" => "",
        "2" => "seller2"
      },
      "series_alias_value" => %{
        "0" => " me ",
        "1" => "ignored",
        "2" => " test "
      },
      "series_priority_item" => %{"0" => " test ", "1" => "me", "2" => " other ", "3" => ""},
      "series_priority_group" => %{"0" => "first", "1" => "first", "2" => "last", "3" => "last"},
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
    assert widget["title"] == "Visual Ordered Series"
    assert widget["series_sort"] == "natural"
    assert widget["series_priority"] == ["test", "me"]
    assert widget["series_priority_last"] == ["other"]
    assert widget["series_aliases"] == %{"seller1" => "me", "seller2" => "test"}
  end

  test "timeseries save uses raw fields when raw mode is selected", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})

    render_submit(view, "save_widget", %{
      "widget_id" => "widget-1",
      "widget_type" => "timeseries",
      "widget_title" => "Raw Ordered Series",
      "ts_chart_type" => "line",
      "series_display_mode" => "raw",
      "series_sort" => "natural",
      "series_aliases" => ~s({"raw": "Raw Alias"}),
      "series_priority" => "raw",
      "series_priority_last" => "raw-last",
      "series_alias_key" => %{"0" => "visual"},
      "series_alias_value" => %{"0" => "Visual Alias"},
      "series_priority_item" => %{"0" => "visual"},
      "series_priority_group" => %{"0" => "last"},
      "widget_series_kind" => %{"0" => "path"},
      "widget_series_path" => %{"0" => "metrics.distribution.*"},
      "widget_series_expression" => %{"0" => ""},
      "widget_series_label" => %{"0" => ""},
      "widget_series_visible" => %{"0" => "true"},
      "widget_series_color_selector" => %{"0" => "default.*"}
    })

    updated = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    [widget] = updated.payload["grid"]

    assert widget["series_priority"] == ["raw"]
    assert widget["series_priority_last"] == ["raw-last"]
    assert widget["series_aliases"] == %{"raw" => "Raw Alias"}
  end

  test "timeseries draft keeps raw editor mode after form changes", %{
    conn: conn,
    dashboard: dashboard
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})

    html =
      render_change(view, "widget_editor_change", %{
        "widget_id" => "widget-1",
        "widget_type" => "timeseries",
        "widget_title" => "Raw Draft",
        "ts_chart_type" => "line",
        "series_display_mode" => "raw",
        "series_aliases" => ~s({"raw": "Raw Alias"}),
        "series_priority" => "raw"
      })

    assert html =~ ~s(name="series_display_mode" value="raw")
    assert html =~ ~s(data-series-display-mode-panel="raw")
  end

  test "timeseries save rejects invalid series aliases JSON", %{
    conn: conn,
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})

    html =
      render_submit(view, "save_widget", %{
        "widget_id" => "widget-1",
        "widget_type" => "timeseries",
        "widget_title" => "Invalid Aliases",
        "ts_chart_type" => "line",
        "series_aliases" => "{",
        "widget_series_kind" => %{"0" => "path"},
        "widget_series_path" => %{"0" => "metrics.distribution.*"},
        "widget_series_expression" => %{"0" => ""},
        "widget_series_label" => %{"0" => ""},
        "widget_series_visible" => %{"0" => "true"},
        "widget_series_color_selector" => %{"0" => "default.*"}
      })

    updated = Organizations.get_dashboard_for_membership!(membership, dashboard.id)
    [widget] = updated.payload["grid"]

    assert html =~ "Aliases must be valid JSON."
    assert widget["type"] == "text"
    refute Map.has_key?(widget, "series_aliases")
  end
end
