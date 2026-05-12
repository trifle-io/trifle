defmodule TrifleApp.ChatShellLiveTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.AccountsFixtures
  alias Trifle.Chat
  alias Trifle.Chat.SessionStore
  alias Trifle.Organizations
  alias Trifle.Stats.Source
  alias TrifleApp.ChatPageContext
  alias TrifleApp.ChatShellLive

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})
    app_entitlement_fixture(organization)
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
    assert html =~ ~s(data-context-slot="chat-context")
    assert html =~ "Context"
    refute html =~ "Current Context"
    refute html =~ "Detected Context"
    refute html =~ "No page detected"
    refute html =~ ~s(data-context-slot="detected-context")
    refute html =~ ~s(data-detected-context-selected=)
    refute html =~ "Next message uses selected source only."
    assert html =~ "h-10 w-10"
    assert html =~ ~s(class="h-5 w-5 shrink-0")
    refute html =~ "Fallback database source"
    assert html =~ ~s(data-chat-shell-mode-group)
    assert html =~ ~s(data-chat-shell-mode-button="pinned")
    assert html =~ ~s(data-chat-shell-mode-button="panel")
    assert html =~ ~s(data-chat-shell-mode-button="fullscreen")
    assert html =~ ~s(data-chat-shell-control="more")
    assert html =~ ~s(data-chat-shell-control="close")
    assert html =~ ~s(data-chat-shell-more-action="source")
    assert html =~ ~s(data-chat-shell-more-action="reset")

    source = Source.from_database(database)

    dashboard_context =
      chat_context(:dashboard, "/dashboards/competitors", "Competitors", source)

    send(view.pid, {:chat_context_updated, dashboard_context})

    html = render(view)
    assert html =~ "Competitors"
    assert html =~ ~s(data-context-slot="detected-context")
    assert html =~ ~s(data-context-compact="true")
    assert html =~ ~s(data-detected-context-selected="false")
    assert html =~ "Switch"
    refute html =~ ">Detected Context<"
    refute html =~ "Next message will switch to this page."
    assert html =~ ~s(data-scope-kind="context")
    assert html =~ ~s(data-scope-icon="sidebar-dashboards")

    html = render_click(view, "toggle_detected_context")
    assert html =~ ~s(data-detected-context-selected="true")
    assert html =~ ~s(data-context-expanded="true")
    assert html =~ ~s(data-context-compact="false")
    assert html =~ "Detected Context"
    refute html =~ "Switch"
    assert html =~ "metrics key sales"

    render_hook(view, "refresh_page_context", %{"path" => "/monitors/baker-agent"})

    html = render(view)
    refute html =~ "Competitors"
    refute html =~ "No page detected"
    refute html =~ ~s(data-context-slot="detected-context")
    refute html =~ ~s(data-detected-context-selected=)
    refute html =~ "Next message uses selected source only."
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

  test "current chat context stays visible separately from detected page context", %{
    conn: conn,
    user: user,
    membership: membership,
    database: database
  } do
    {:ok, view, _html} =
      live_isolated(conn, ChatShellLive,
        session: %{
          "current_user_id" => to_string(user.id),
          "current_membership_id" => to_string(membership.id)
        },
        connect_params: %{"tab_id" => "chat-shell-current-detected-context-test"}
      )

    source = Source.from_database(database)

    dashboard_context =
      chat_context(:dashboard, "/dashboards/competitors", "Competitors", source)

    {:ok, session} = Chat.ensure_workspace_session(user, membership)

    {:ok, _session} =
      SessionStore.append_message(session, %{
        role: "system",
        content: ChatPageContext.system_message(dashboard_context)
      })

    assert_eventually_renders(view, "Context")
    html = render(view)
    assert html =~ ~s(data-context-slot="chat-context")
    assert html =~ "Competitors"
    refute html =~ "Current Context"
    refute html =~ "Currently attached to this conversation."

    same_dashboard_different_query =
      chat_context(:dashboard, "/dashboards/competitors", "Competitors", source, %{
        timeframe: %{value: "7d"},
        granularity: "1d",
        metrics_key: "revenue"
      })

    send(view.pid, {:chat_context_updated, same_dashboard_different_query})

    html = render(view)
    refute html =~ ~s(data-context-slot="detected-context")
    refute html =~ ~s(data-detected-context-selected=)
    refute html =~ "Switch"
    refute html =~ ">Detected Context<"
    refute html =~ "Next message uses this page."

    render_hook(view, "refresh_page_context", %{"path" => "/monitors/baker-agent"})

    html = render(view)
    assert html =~ "Competitors"
    refute html =~ "No page detected"
    refute html =~ ~s(data-context-slot="detected-context")
    refute html =~ "Next message uses selected source only."

    monitor_context =
      chat_context(:monitor, "/monitors/baker-agent", "Baker Agent Monitor", source)

    send(view.pid, {:chat_context_updated, monitor_context})

    html = render(view)
    assert html =~ "Competitors"
    assert html =~ "Baker Agent Monitor"
    assert html =~ ~s(data-context-slot="detected-context")
    assert html =~ "Switch"
    refute html =~ "Next message will switch to this page."
  end

  test "session messages and progress synchronize across open chat shells", %{
    conn: conn,
    user: user,
    membership: membership
  } do
    {:ok, first_view, _html} =
      live_isolated(conn, ChatShellLive,
        session: %{
          "current_user_id" => to_string(user.id),
          "current_membership_id" => to_string(membership.id)
        },
        connect_params: %{"tab_id" => "chat-sync-first"}
      )

    {:ok, second_view, _html} =
      live_isolated(conn, ChatShellLive,
        session: %{
          "current_user_id" => to_string(user.id),
          "current_membership_id" => to_string(membership.id)
        },
        connect_params: %{"tab_id" => "chat-sync-second"}
      )

    {:ok, session} = Chat.ensure_workspace_session(user, membership)

    {:ok, session} =
      SessionStore.append_message(session, %{
        role: "user",
        content: "Can both tabs see this?"
      })

    assert_eventually_renders(first_view, "Can both tabs see this?")
    assert_eventually_renders(second_view, "Can both tabs see this?")

    {:ok, pending_session} = SessionStore.reset_progress(session, DateTime.utc_now())

    assert_eventually_renders(first_view, "Waiting for AI response.")
    assert_eventually_renders(second_view, "Waiting for AI response.")

    {:ok, assistant_session} =
      SessionStore.append_message(pending_session, %{
        role: "assistant",
        content: "Yes, both tabs are synced."
      })

    {:ok, _session} = SessionStore.clear_pending(assistant_session)

    assert_eventually_renders(first_view, "Yes, both tabs are synced.")
    assert_eventually_renders(second_view, "Yes, both tabs are synced.")
  end

  test "session updates for another chat id are ignored", %{
    conn: conn,
    user: user,
    membership: membership
  } do
    {:ok, view, _html} =
      live_isolated(conn, ChatShellLive,
        session: %{
          "current_user_id" => to_string(user.id),
          "current_membership_id" => to_string(membership.id)
        },
        connect_params: %{"tab_id" => "chat-sync-ignored"}
      )

    {:ok, _active_session} = Chat.ensure_workspace_session(user, membership)

    {:ok, other_session} =
      SessionStore.create(to_string(user.id), to_string(membership.organization_id), %{
        type: "workspace",
        id: Ecto.UUID.generate()
      })

    {:ok, _other_session} =
      SessionStore.append_message(other_session, %{
        role: "user",
        content: "This belongs to another chat."
      })

    refute render(view) =~ "This belongs to another chat."
  end

  test "submitting a message persists it to the shared session before completion", %{
    conn: conn,
    user: user,
    membership: membership
  } do
    {:ok, view, _html} =
      live_isolated(conn, ChatShellLive,
        session: %{
          "current_user_id" => to_string(user.id),
          "current_membership_id" => to_string(membership.id)
        }
      )

    {:ok, session} = Chat.ensure_workspace_session(user, membership)

    render_submit(view, "send_message", %{
      "chat" => %{"message" => "Persist this prompt for every tab"}
    })

    assert_eventually_session_message(session.id, "Persist this prompt for every tab")
    assert_eventually_renders(view, "Persist this prompt for every tab")
  end

  test "submitting a message keeps the existing context by default", %{
    conn: conn,
    user: user,
    membership: membership,
    database: database
  } do
    {:ok, view, _html} =
      live_isolated(conn, ChatShellLive,
        session: %{
          "current_user_id" => to_string(user.id),
          "current_membership_id" => to_string(membership.id)
        },
        connect_params: %{"tab_id" => "chat-context-send-default"}
      )

    source = Source.from_database(database)
    dashboard_context = chat_context(:dashboard, "/dashboards/competitors", "Competitors", source)

    monitor_context =
      chat_context(:monitor, "/monitors/baker-agent", "Baker Agent Monitor", source)

    {:ok, session} = Chat.ensure_workspace_session(user, membership)

    {:ok, _session} =
      SessionStore.append_message(session, %{
        role: "system",
        content: ChatPageContext.system_message(dashboard_context)
      })

    assert_eventually_renders(view, "Competitors")
    send(view.pid, {:chat_context_updated, monitor_context})

    html = assert_eventually_renders(view, "Baker Agent Monitor")
    assert html =~ ~s(data-detected-context-selected="false")

    render_submit(view, "send_message", %{
      "chat" => %{"message" => "Keep dashboard context"}
    })

    assert_eventually_session_message(session.id, "Keep dashboard context")
    {:ok, updated_session} = SessionStore.get(session.id)

    assert latest_context_title(updated_session) == "Competitors"
    refute "Baker Agent Monitor" in system_context_titles(updated_session)
  end

  test "submitting a message switches to detected context when selected", %{
    conn: conn,
    user: user,
    membership: membership,
    database: database
  } do
    {:ok, view, _html} =
      live_isolated(conn, ChatShellLive,
        session: %{
          "current_user_id" => to_string(user.id),
          "current_membership_id" => to_string(membership.id)
        },
        connect_params: %{"tab_id" => "chat-context-send-detected"}
      )

    source = Source.from_database(database)
    dashboard_context = chat_context(:dashboard, "/dashboards/competitors", "Competitors", source)

    monitor_context =
      chat_context(:monitor, "/monitors/baker-agent", "Baker Agent Monitor", source)

    {:ok, session} = Chat.ensure_workspace_session(user, membership)

    {:ok, _session} =
      SessionStore.append_message(session, %{
        role: "system",
        content: ChatPageContext.system_message(dashboard_context)
      })

    assert_eventually_renders(view, "Competitors")
    send(view.pid, {:chat_context_updated, monitor_context})
    assert_eventually_renders(view, "Baker Agent Monitor")

    html = render_click(view, "toggle_detected_context")
    assert html =~ ~s(data-detected-context-selected="true")

    render_submit(view, "send_message", %{
      "chat" => %{"message" => "Use monitor context"}
    })

    assert_eventually_session_message(session.id, "Use monitor context")
    assert_eventually_session_context(session.id, "Baker Agent Monitor")
  end

  defp chat_context(page_type, route, title, source, query_overrides \\ %{}) do
    query =
      %{
        source_ref: ChatPageContext.source_ref(source),
        timeframe: %{value: "24h"},
        granularity: "1h",
        metrics_key: "sales"
      }
      |> Map.merge(query_overrides)

    ChatPageContext.build(page_type,
      entity: %{
        id: "#{page_type}-scope",
        title: title,
        route: route
      },
      query: query
    )
  end

  defp assert_eventually_renders(view, text) do
    html =
      Enum.reduce_while(1..25, nil, fn _, _last_html ->
        html = render(view)

        if html =~ text do
          {:halt, html}
        else
          Process.sleep(10)
          {:cont, html}
        end
      end)

    assert is_binary(html) and html =~ text
    html
  end

  defp assert_eventually_session_message(session_id, text) do
    messages =
      Enum.reduce_while(1..60, [], fn _, _last_messages ->
        messages =
          case SessionStore.get(session_id) do
            {:ok, session} -> session.messages
            _ -> []
          end

        if Enum.any?(messages, &(Map.get(&1, :content) == text)) do
          {:halt, messages}
        else
          Process.sleep(10)
          {:cont, messages}
        end
      end)

    assert Enum.any?(messages, &(Map.get(&1, :content) == text))
  end

  defp assert_eventually_session_context(session_id, title) do
    context_title =
      Enum.reduce_while(1..40, nil, fn _, _last_title ->
        context_title =
          case SessionStore.get(session_id) do
            {:ok, session} -> latest_context_title(session)
            _ -> nil
          end

        if context_title == title do
          {:halt, context_title}
        else
          Process.sleep(10)
          {:cont, context_title}
        end
      end)

    assert context_title == title
  end

  defp latest_context_title(session) do
    session
    |> system_context_titles()
    |> List.last()
  end

  defp system_context_titles(session) do
    session.messages
    |> Enum.filter(&(Map.get(&1, :role, Map.get(&1, "role")) == "system"))
    |> Enum.map(fn message ->
      message
      |> Map.get(:content, Map.get(message, "content"))
      |> ChatPageContext.parse_system_message()
      |> context_title()
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp context_title(nil), do: nil

  defp context_title(context) do
    context
    |> Map.get(:entity, %{})
    |> Map.get("title")
  end
end
