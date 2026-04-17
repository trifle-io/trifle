defmodule TrifleApp.ChatShellLiveTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.OrganizationsFixtures

  alias Trifle.AccountsFixtures
  alias Trifle.Organizations
  alias Trifle.Stats.Source
  alias TrifleApp.ChatPageContext
  alias TrifleApp.ChatShellLive

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})
    membership = Organizations.get_membership_for_user(user)

    database =
      database_fixture(%{
        organization: organization,
        display_name: "Sales Mongo"
      })

    {:ok, conn: conn, user: user, membership: membership, database: database}
  end

  test "scope card tracks current page context across navigation", %{
    conn: conn,
    user: user,
    membership: membership,
    database: database
  } do
    {:ok, view, html} =
      live_isolated(conn, ChatShellLive,
        session: %{
          "current_user_id" => to_string(user.id),
          "current_membership_id" => to_string(membership.id)
        },
        connect_params: %{"tab_id" => "chat-shell-context-test"}
      )

    assert html =~ "Sales Mongo"
    assert html =~ ~s(data-scope-kind="source")
    assert html =~ ~s(data-scope-icon="sidebar-databases")
    assert html =~ ~s(class="flex h-10 w-10 shrink-0 items-center justify-center)
    assert html =~ ~s(class="h-5 w-5 shrink-0")
    refute html =~ "Fallback database source"

    source = Source.from_database(database)

    dashboard_context =
      chat_context(:dashboard, "/dashboards/competitors", "Competitors", source)

    send(view.pid, {:chat_context_updated, dashboard_context})

    html = render(view)
    assert html =~ "Competitors"
    assert html =~ ~s(data-scope-kind="context")
    assert html =~ ~s(data-scope-icon="sidebar-dashboards")

    render_hook(view, "refresh_page_context", %{"path" => "/monitors/baker-agent"})

    html = render(view)
    refute html =~ "Competitors"
    assert html =~ "Sales Mongo"
    assert html =~ ~s(data-scope-kind="source")
    assert html =~ ~s(data-scope-icon="sidebar-databases")

    send(view.pid, {:chat_context_updated, dashboard_context})

    html = render(view)
    refute html =~ "Competitors"

    monitor_context =
      chat_context(:monitor, "/monitors/baker-agent", "Baker Agent Monitor", source)

    send(view.pid, {:chat_context_updated, monitor_context})

    html = render(view)
    assert html =~ "Baker Agent Monitor"
    assert html =~ ~s(data-scope-kind="context")
    assert html =~ ~s(data-scope-icon="sidebar-monitors")
  end

  defp chat_context(page_type, route, title, source) do
    ChatPageContext.build(page_type,
      entity: %{
        id: "#{page_type}-scope",
        title: title,
        route: route
      },
      query: %{
        source_ref: ChatPageContext.source_ref(source),
        timeframe: %{value: "24h"},
        granularity: "1h",
        metrics_key: "sales"
      }
    )
  end
end
