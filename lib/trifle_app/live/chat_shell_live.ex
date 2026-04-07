defmodule TrifleApp.ChatShellLive do
  use TrifleApp, :live_view
  require Logger

  alias Ecto.UUID
  alias Trifle.Accounts
  alias Trifle.Chat
  alias Trifle.Chat.Bus, as: SessionBus
  alias Trifle.Chat.InlineDashboard
  alias Trifle.Chat.Progress
  alias Trifle.Chat.RunnerRegistry
  alias Trifle.Chat.Session
  alias Trifle.Chat.SessionStore
  alias Trifle.Organizations
  alias Trifle.Stats.Source
  alias TrifleApp.ChatBus
  alias TrifleApp.ChatPageContext
  alias TrifleApp.Components.DashboardPayload
  alias TrifleApp.Components.DashboardWidgets.WidgetView

  @chat_cancel_reason :chat_cancelled
  @context_request_timeout_ms 250
  @initial_context_request_delay_ms 75
  @navigation_context_request_delay_ms 75
  @page_action_timeout_ms 5_000

  @impl true
  def mount(_params, session, socket) do
    current_user = socket.assigns[:current_user] || load_current_user(session)
    membership = socket.assigns[:current_membership] || load_current_membership(session)

    organization =
      socket.assigns[:current_organization] || (membership && membership.organization)

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:current_membership, membership)
      |> assign(:current_organization, organization)

    cond do
      is_nil(current_user) or is_nil(membership) ->
        {:ok,
         socket
         |> assign_shell_defaults([])
         |> assign(:show_unavailable_notice, true), layout: false}

      true ->
        sources = Source.list_for_membership(membership)
        fallback_source = List.first(sources)

        socket =
          socket
          |> ChatBus.maybe_subscribe_page_channel()
          |> assign_shell_defaults(sources)
          |> assign(:selected_source, fallback_source)
          |> assign(:show_unavailable_notice, false)

        socket =
          case Chat.ensure_workspace_session(current_user, membership) do
            {:ok, session} ->
              socket
              |> assign(:session, session)
              |> assign_messages(session)
              |> assign(:session_page_context, session_page_context(session))
              |> maybe_subscribe_session(session)
              |> maybe_request_initial_context()
              |> maybe_resume_pending()

            {:error, reason} ->
              put_flash(socket, :error, "Unable to load chat session: #{format_error(reason)}")
          end

        {:ok, socket, layout: false}
    end
  end

  defp load_current_user(%{"current_user_id" => id}) when is_binary(id) and id != "" do
    Accounts.get_user!(id)
  rescue
    Ecto.NoResultsError ->
      Logger.debug("ChatShellLive: no user found for id: #{id}")
      nil
  end

  defp load_current_user(_session), do: nil

  defp load_current_membership(%{"current_membership_id" => id})
       when is_binary(id) and id != "" do
    Organizations.get_membership!(id)
  rescue
    Ecto.NoResultsError ->
      Logger.debug("ChatShellLive: no membership found for id: #{id}")
      nil
  end

  defp load_current_membership(_session), do: nil

  @impl true
  def handle_event("send_message", %{"chat" => %{"message" => message}}, socket) do
    submit_message(socket, message)
  end

  def handle_event("starter_message", %{"message" => message}, socket) do
    submit_message(socket, message)
  end

  def handle_event("cancel_message", _params, socket) do
    socket =
      socket
      |> release_chat_run()
      |> cancel_async(:chat_response, @chat_cancel_reason)
      |> cancel_progress_timer()
      |> cancel_context_request()

    {socket, session} = restore_session_snapshot(socket)
    message = socket.assigns[:pending_user_message] || ""

    socket =
      socket
      |> assign(:sending, false)
      |> assign_messages(session)
      |> assign(:progress_events, [])
      |> assign(:progress_started_at, nil)
      |> assign(:progress_stage_started_at, nil)
      |> assign(:progress_tick_at, nil)
      |> assign(:form, to_form(%{"message" => message}))
      |> assign(:pending_user_message, nil)
      |> assign(:session_snapshot, nil)
      |> assign(:pending_context_request_id, nil)
      |> assign(:pending_page_context_override, nil)

    {:noreply, socket}
  end

  def handle_event("reset_chat", _params, %{assigns: %{session: %Session{} = session}} = socket) do
    case Chat.reset(session) do
      {:ok, reset_session} ->
        socket =
          socket
          |> release_chat_run()
          |> cancel_async(:chat_response, @chat_cancel_reason)
          |> cancel_progress_timer()
          |> cancel_context_request()
          |> assign(:session, reset_session)
          |> assign_messages(reset_session)
          |> assign(:sending, false)
          |> assign(:progress_events, [])
          |> assign(:progress_started_at, nil)
          |> assign(:progress_stage_started_at, nil)
          |> assign(:progress_tick_at, nil)
          |> assign(:session_snapshot, nil)
          |> assign(:pending_user_message, nil)
          |> assign(:pending_context_request_id, nil)
          |> assign(:pending_page_context_override, nil)
          |> assign(:form, to_form(%{"message" => ""}))

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not reset chat: #{format_error(reason)}")}
    end
  end

  def handle_event("reset_chat", _params, socket), do: {:noreply, socket}

  def handle_event("open_source_modal", _params, socket) do
    {:noreply, assign(socket, :show_source_modal, true)}
  end

  def handle_event("close_source_modal", _params, socket) do
    {:noreply, assign(socket, :show_source_modal, false)}
  end

  def handle_event("select_source", %{"ref" => ref}, socket) do
    case parse_source_ref(ref, socket.assigns.sources) do
      nil ->
        {:noreply,
         socket
         |> assign(:show_source_modal, false)
         |> put_flash(:error, "Unknown analytics source.")}

      source ->
        {:noreply,
         socket
         |> assign(:selected_source, source)
         |> assign(:show_source_modal, false)}
    end
  end

  def handle_event(
        "open_dashboard_payload",
        %{"dom_id" => dom_id, "message_id" => message_id},
        socket
      ) do
    if socket.assigns[:can_view_dashboard_payload] do
      case find_dashboard_visualization(socket.assigns.messages, dom_id, message_id) do
        nil ->
          {:noreply, put_flash(socket, :error, "Dashboard payload unavailable.")}

        visualization ->
          {:noreply,
           socket
           |> assign(:show_dashboard_payload_modal, true)
           |> assign(:selected_dashboard_payload_title, dashboard_payload_title(visualization))
           |> assign(
             :selected_dashboard_payload,
             DashboardPayload.dashboard_payload_json(
               Map.get(visualization, :dashboard, Map.get(visualization, "dashboard", %{}))
             )
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_dashboard_payload_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_dashboard_payload_modal, false)
     |> assign(:selected_dashboard_payload, nil)
     |> assign(:selected_dashboard_payload_title, nil)}
  end

  def handle_event(
        "preview_dashboard_update",
        %{"dom_id" => dom_id, "message_id" => message_id},
        socket
      ) do
    if can_apply_dashboard_update?(socket.assigns[:current_page_context]) do
      case find_dashboard_visualization(socket.assigns.messages, dom_id, message_id) do
        nil ->
          {:noreply, put_flash(socket, :error, "Dashboard preview unavailable.")}

        visualization ->
          dashboard = Map.get(visualization, :dashboard, Map.get(visualization, "dashboard", %{}))

          {:noreply,
           socket
           |> assign(:selected_visualization, visualization)
           |> assign(:show_dashboard_preview_modal, true)
           |> assign(:selected_dashboard_payload_title, dashboard_payload_title(visualization))
           |> assign(
             :selected_dashboard_payload,
             DashboardPayload.dashboard_payload_json(dashboard)
           )}
      end
    else
      {:noreply,
       put_flash(socket, :error, "Open a dashboard page first to preview an in-place update.")}
    end
  end

  def handle_event("close_dashboard_preview_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_dashboard_preview_modal, false)
     |> assign(:selected_visualization, nil)}
  end

  def handle_event(
        "create_dashboard_from_visualization",
        %{"dom_id" => dom_id, "message_id" => message_id},
        socket
      ) do
    case find_dashboard_visualization(socket.assigns.messages, dom_id, message_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Dashboard visualization unavailable.")}

      visualization ->
        with {:ok, attrs} <- dashboard_create_attrs(socket, visualization),
             {:ok, dashboard} <-
               Organizations.create_dashboard_for_membership(
                 socket.assigns.current_user,
                 socket.assigns.current_membership,
                 attrs
               ) do
          {:noreply,
           socket
           |> assign(:show_dashboard_preview_modal, false)
           |> put_flash(:info, "Created dashboard #{dashboard.name}")
           |> push_navigate(to: ~p"/dashboards/#{dashboard.id}")}
        else
          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Could not create dashboard: #{format_error(reason)}")}
        end
    end
  end

  def handle_event("apply_dashboard_update", _params, socket) do
    request_id = UUID.generate()

    with true <- can_apply_dashboard_update?(socket.assigns[:current_page_context]),
         %{} = visualization <- socket.assigns[:selected_visualization],
         user_id when is_binary(user_id) <- current_user_id(socket),
         tab_id when is_binary(tab_id) <- socket.assigns[:chat_tab_id] do
      action = %{
        type: "dashboard_apply_update",
        visualization: visualization
      }

      ChatBus.send_page_action(user_id, tab_id, request_id, self(), action)

      timer_ref =
        Process.send_after(
          self(),
          {:pending_page_action_request_timeout, request_id},
          @page_action_timeout_ms
        )

      {:noreply,
       socket
       |> cancel_pending_page_action_request()
       |> assign(:pending_page_action_request_id, request_id)
       |> assign(:pending_page_action, :dashboard_apply_update)
       |> assign(:pending_page_action_timer_ref, timer_ref)}
    else
      _ ->
        {:noreply,
         put_flash(socket, :error, "Open an editable dashboard page before applying the update.")}
    end
  end

  def handle_event("refresh_page_context", _params, socket) do
    cond do
      not connected?(socket) ->
        {:noreply, socket}

      not is_binary(current_user_id(socket)) ->
        {:noreply, clear_current_page_context(socket)}

      not is_binary(socket.assigns[:chat_tab_id]) ->
        {:noreply, clear_current_page_context(socket)}

      true ->
        request_id = UUID.generate()

        socket =
          socket
          |> cancel_navigation_context_request()
          |> assign(:navigation_context_request_id, request_id)
          |> assign(
            :navigation_context_timer_ref,
            Process.send_after(
              self(),
              {:chat_navigation_context_timeout, request_id},
              @context_request_timeout_ms + @navigation_context_request_delay_ms
            )
          )

        Process.send_after(
          self(),
          {:request_navigation_chat_context, request_id},
          @navigation_context_request_delay_ms
        )

        {:noreply, socket}
    end
  end

  @impl true
  def handle_async(:chat_response, {:ok, {:ok, session, latest_message}}, socket) do
    socket =
      socket
      |> release_chat_run()
      |> assign(:session, session)
      |> assign_messages(session)
      |> assign(:sending, false)
      |> assign(:session_snapshot, nil)
      |> assign(:pending_user_message, nil)
      |> assign(:pending_context_request_id, nil)
      |> assign(:pending_page_context_override, nil)
      |> maybe_subscribe_session(session)
      |> maybe_flash_tool_error(latest_message)
      |> append_final_duration()

    {:noreply, socket |> push_event("chat_scroll_bottom", %{})}
  end

  def handle_async(:chat_response, {:ok, {:error, %{status: :missing_api_key} = error}}, socket) do
    socket =
      socket
      |> release_chat_run()
      |> assign(:sending, false)
      |> assign(:session, reload_session(socket.assigns.session))
      |> assign(:session_snapshot, nil)
      |> assign(:pending_user_message, nil)
      |> assign(:pending_context_request_id, nil)
      |> assign(:pending_page_context_override, nil)
      |> put_flash(:error, format_error(error))
      |> append_final_duration()

    {:noreply, socket}
  end

  def handle_async(:chat_response, {:ok, {:error, reason}}, socket) do
    socket =
      socket
      |> release_chat_run()
      |> assign(:sending, false)
      |> assign(:session, reload_session(socket.assigns.session))
      |> assign(:session_snapshot, nil)
      |> assign(:pending_user_message, nil)
      |> assign(:pending_context_request_id, nil)
      |> assign(:pending_page_context_override, nil)
      |> put_flash(:error, format_error(reason))
      |> append_final_duration()

    {:noreply, socket}
  end

  def handle_async(:chat_response, {:exit, reason}, socket)
      when reason in [@chat_cancel_reason, {:shutdown, :cancel}] do
    socket =
      socket
      |> release_chat_run()
      |> assign(:sending, false)
      |> assign(:session_snapshot, nil)
      |> assign(:pending_user_message, nil)
      |> assign(:pending_context_request_id, nil)
      |> assign(:pending_page_context_override, nil)
      |> cancel_progress_timer()
      |> assign(:progress_events, [])
      |> assign(:progress_started_at, nil)
      |> assign(:progress_stage_started_at, nil)
      |> assign(:progress_tick_at, nil)

    {:noreply, socket}
  end

  def handle_async(:chat_response, {:exit, reason}, socket) do
    socket =
      socket
      |> release_chat_run()
      |> assign(:sending, false)
      |> assign(:session_snapshot, nil)
      |> assign(:pending_user_message, nil)
      |> assign(:pending_context_request_id, nil)
      |> assign(:pending_page_context_override, nil)
      |> put_flash(:error, "Chat process crashed: #{inspect(reason)}")
      |> append_final_duration()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:chat_context_updated, context}, socket) when is_map(context) do
    {:noreply,
     socket
     |> cancel_initial_context_request()
     |> cancel_navigation_context_request()
     |> assign(:current_page_context, context)
     |> maybe_resume_pending()}
  end

  def handle_info({:chat_context_response, request_id, context}, socket) do
    cond do
      request_id == socket.assigns[:pending_context_request_id] ->
        socket =
          socket
          |> cancel_context_request()
          |> assign(:current_page_context, context)
          |> assign(:pending_page_context_override, context)

        {:noreply, start_chat_response(socket, context)}

      request_id == socket.assigns[:initial_context_request_id] ->
        socket =
          socket
          |> cancel_initial_context_request()
          |> assign(:current_page_context, context)

        {:noreply, maybe_resume_pending(socket)}

      request_id == socket.assigns[:navigation_context_request_id] ->
        {:noreply,
         socket
         |> cancel_navigation_context_request()
         |> assign(:current_page_context, context)}

      true ->
        {:noreply, socket}
    end
  end

  def handle_info({:initial_chat_context_timeout, request_id}, socket) do
    if request_id == socket.assigns[:initial_context_request_id] do
      {:noreply, socket |> cancel_initial_context_request() |> maybe_resume_pending()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:request_initial_chat_context, request_id}, socket) do
    if request_id == socket.assigns[:initial_context_request_id] do
      request_page_context(socket, request_id)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:request_navigation_chat_context, request_id}, socket) do
    if request_id == socket.assigns[:navigation_context_request_id] do
      request_page_context(socket, request_id)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:chat_context_timeout, request_id}, socket) do
    if request_id == socket.assigns[:pending_context_request_id] do
      socket =
        socket
        |> assign(:pending_context_request_id, nil)
        |> assign(:pending_context_timer_ref, nil)

      {:noreply, start_chat_response(socket, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:chat_navigation_context_timeout, request_id}, socket) do
    if request_id == socket.assigns[:navigation_context_request_id] do
      {:noreply,
       socket
       |> cancel_navigation_context_request()
       |> clear_current_page_context()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:pending_page_action_request_timeout, request_id}, socket) do
    if request_id == socket.assigns[:pending_page_action_request_id] do
      {:noreply,
       socket
       |> cancel_pending_page_action_request()
       |> put_flash(:error, "Dashboard update timed out. Try again.")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:chat_page_action_result, request_id, {:ok, result}}, socket) do
    if request_id == socket.assigns[:pending_page_action_request_id] do
      socket =
        socket
        |> cancel_pending_page_action_request()
        |> assign(:show_dashboard_preview_modal, false)
        |> assign(:selected_visualization, nil)
        |> put_flash(
          :info,
          Map.get(result, :message, Map.get(result, "message", "Dashboard updated successfully"))
        )

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:chat_page_action_result, request_id, {:error, reason}}, socket) do
    if request_id == socket.assigns[:pending_page_action_request_id] do
      socket =
        socket
        |> cancel_pending_page_action_request()
        |> put_flash(:error, format_error(reason))

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:chat_session_updated, session_id, %Session{} = session}, socket) do
    if session_id == socket.assigns[:chat_session_id] do
      socket =
        socket
        |> assign(:session, session)
        |> assign_messages(session)
        |> sync_progress_from_session(session)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:chat_progress, {:progress, type}}, socket) do
    handle_progress_event(socket, type, %{})
  end

  def handle_info({:chat_progress, {:progress, type, payload}}, socket) do
    handle_progress_event(socket, type, payload)
  end

  def handle_info(:progress_tick, socket) do
    socket = assign(socket, :progress_timer_ref, nil)

    if active_progress?(socket.assigns.progress_events) do
      now = DateTime.utc_now()

      socket =
        socket
        |> assign(:progress_tick_at, now)
        |> ensure_progress_timer()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(message, socket) do
    Logger.debug("ChatShellLive: unhandled message #{inspect(message)}")
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id="chat-shell-panel"
      class="h-full"
      phx-hook="ChatContextRefresh"
      data-chat-context-refresh="true"
    >
      <div
        id="chat-shell-fast-tooltip"
        class="flex h-full flex-col overflow-hidden"
        phx-hook="FastTooltip"
      >
        <div class="relative border-b border-slate-200/80 px-5 py-4 dark:border-slate-800/80">
          <div class="flex items-center justify-between gap-3">
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2.5">
                <div class="flex shrink-0 items-center gap-1.5 text-slate-500 dark:text-slate-400">
                  <TrifleApp.SidebarIcons.icon name="chef-hat-alt-2" class="h-7 w-7" />
                </div>
                <h2 class="truncate text-lg font-semibold leading-none text-slate-900 dark:text-white">
                  Baker Agent
                </h2>
              </div>
            </div>

            <div class="flex shrink-0 items-center gap-2">
              <button
                type="button"
                phx-click="open_source_modal"
                class="inline-flex h-9 items-center rounded-xl border border-slate-200 bg-white px-3 text-xs font-medium text-slate-600 transition hover:border-teal-400 hover:text-slate-900 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-300 dark:hover:border-teal-400 dark:hover:text-white"
              >
                Source
              </button>
              <button
                type="button"
                phx-click="reset_chat"
                class="inline-flex h-9 items-center rounded-xl border border-slate-200 bg-white px-3 text-xs font-medium text-slate-600 transition hover:border-amber-300 hover:text-slate-900 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-300 dark:hover:border-amber-400 dark:hover:text-white"
              >
                Reset
              </button>
              <button
                type="button"
                onclick="window.dispatchEvent(new CustomEvent('trifle:chat-shell:set-open', { detail: { open: false } }))"
                class="inline-flex h-9 w-9 items-center justify-center rounded-xl border border-slate-200 bg-white text-slate-500 transition hover:border-slate-300 hover:text-slate-900 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-400 dark:hover:border-slate-500 dark:hover:text-white"
                aria-label="Close chat"
              >
                <TrifleApp.SidebarIcons.icon name="hero-x-mark" class="h-4 w-4" />
              </button>
            </div>
          </div>

          <p :if={@show_unavailable_notice} class="mt-3 text-xs text-slate-500 dark:text-slate-400">
            Join or create an organization to use the persistent chat shell.
          </p>
          <div :if={@current_page_context} class="mt-3 text-sm text-slate-600 dark:text-slate-300">
            <span class="font-semibold text-slate-700 dark:text-slate-100">Context:</span>
            {current_context_summary(@current_page_context)}
          </div>
        </div>

        <div
          id="chat-messages"
          class="flex-1 overflow-y-auto px-5 py-4"
          data-chat-container
          phx-hook="ChatScroll"
        >
          <div class="space-y-4">
            <.no_source_notice :if={@messages == [] and is_nil(displayed_source(@selected_source))} />

            <% {messages_without_last, last_message} = split_messages(@messages) %>

            <.chat_message
              :for={message <- messages_without_last}
              message={message}
              current_user={@current_user}
              can_view_dashboard_payload={@can_view_dashboard_payload}
              can_apply_dashboard_update={can_apply_dashboard_update?(@current_page_context)}
            />

            <.progress_events
              :if={progress_before_last?(@progress_events, @sending, last_message)}
              events={@progress_events}
              active={@sending}
              tick_at={@progress_tick_at}
            />

            <.chat_message
              :if={last_message}
              message={last_message}
              current_user={@current_user}
              can_view_dashboard_payload={@can_view_dashboard_payload}
              can_apply_dashboard_update={can_apply_dashboard_update?(@current_page_context)}
            />

            <.progress_events
              :if={progress_after_last?(@progress_events, @sending, last_message)}
              events={@progress_events}
              active={@sending}
              tick_at={@progress_tick_at}
            />

            <div
              :if={@messages == [] and displayed_source(@selected_source)}
              class="rounded-2xl bg-slate-50/70 px-4 py-4 dark:bg-slate-900/30"
            >
              <p class="text-base font-semibold text-slate-900 dark:text-slate-100">
                Ask me anything about your data.
              </p>
              <p class="mb-3 mt-1 text-sm leading-6 text-slate-600 dark:text-slate-300">
                I can help you explore current activity, summarize performance over time, analyze
                trends, spot anomalies, and forecast what might happen next.
              </p>
              <div class="flex flex-wrap gap-2">
                <button
                  :for={prompt <- starter_prompts()}
                  type="button"
                  phx-click="starter_message"
                  phx-value-message={prompt.message}
                  class="inline-flex items-center rounded-full border border-slate-200 bg-white px-3 py-2 text-left text-sm font-medium text-slate-700 shadow-sm transition hover:border-teal-300 hover:text-teal-700 dark:border-slate-700 dark:bg-slate-900/70 dark:text-slate-200 dark:hover:border-teal-500/60 dark:hover:text-teal-300"
                  disabled={@show_unavailable_notice or @sending}
                >
                  {prompt.label}
                </button>
              </div>
            </div>
          </div>
        </div>

        <div class="border-t border-slate-200/80 px-5 pb-5 pt-4 dark:border-slate-800/80">
          <% selected_source = displayed_source(@selected_source) %>
          <.source_tag :if={selected_source} source={selected_source} class="mb-1" />
          <.form for={@form} phx-submit="send_message" class="mt-auto">
            <div class="relative overflow-hidden rounded-2xl border border-transparent bg-white/70 shadow-lg backdrop-blur-xl focus-within:border-teal-500/60 dark:border-slate-700 dark:bg-slate-900/50 dark:shadow-none dark:focus-within:border-teal-400">
              <div class="flex items-end">
                <textarea
                  id="chat-message-input"
                  name="chat[message]"
                  rows="3"
                  placeholder="Ask me about your metrics..."
                  class="flex-1 resize-none border-0 bg-transparent px-4 py-4 text-sm text-slate-900 focus:border-0 focus:ring-0 dark:text-slate-100"
                  phx-hook="ChatInput"
                  required
                  disabled={@show_unavailable_notice or @sending}
                ><%= Phoenix.HTML.Form.input_value(@form, :message) %></textarea>

                <%= if @sending do %>
                  <button
                    type="button"
                    phx-click="cancel_message"
                    class="mb-3 mr-3 inline-flex items-center justify-center rounded-xl bg-rose-500 px-4 py-3 text-sm text-white shadow-sm hover:bg-rose-600"
                  >
                    <TrifleApp.SidebarIcons.icon name="hero-x-mark" class="h-4 w-4" />
                  </button>
                <% else %>
                  <button
                    type="submit"
                    class="mb-3 mr-3 inline-flex items-center justify-center rounded-xl bg-teal-600 px-4 py-3 text-sm text-white shadow-sm hover:bg-teal-700 disabled:cursor-not-allowed disabled:opacity-60"
                    disabled={@show_unavailable_notice}
                  >
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke-width="1.5"
                      stroke="currentColor"
                      class="h-5 w-5"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        d="M6 12 3.269 3.125A59.769 59.769 0 0 1 21.485 12 59.768 59.768 0 0 1 3.27 20.875L5.999 12Zm0 0h7.5"
                      />
                    </svg>
                  </button>
                <% end %>
              </div>
            </div>
          </.form>
        </div>

        <.app_modal
          id="chat-source-modal"
          show={@show_source_modal}
          on_cancel="close_source_modal"
          size="md"
        >
          <:title>Fallback analytics source</:title>
          <:body>
            <p class="mb-4 text-sm text-slate-600 dark:text-slate-300">
              The current page usually provides the active source. Use this when you want a fallback
              source while chatting from a page without source context.
            </p>

            <%= if Enum.empty?(@grouped_sources) do %>
              <p class="text-sm text-slate-600 dark:text-slate-300">
                Add a database or project to start chatting with Baker Agent.
              </p>
            <% else %>
              <div class="space-y-6">
                <%= for group <- @grouped_sources do %>
                  <div>
                    <p class="text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">
                      {group.label}
                    </p>
                    <div class="mt-3 space-y-2">
                      <%= for source <- group.sources do %>
                        <button
                          type="button"
                          phx-click="select_source"
                          phx-value-ref={encode_source_ref(source)}
                          class={source_option_classes(source, @selected_source)}
                        >
                          <div class="flex items-center justify-between gap-4">
                            <div class="flex flex-col">
                              <span class="text-sm font-medium text-slate-900 dark:text-slate-100">
                                {Source.display_name(source)}
                              </span>
                              <span class="text-xs text-slate-500 dark:text-slate-400">
                                {source_option_hint(source)}
                              </span>
                            </div>
                            <%= if source_selected?(source, @selected_source) do %>
                              <span class="text-xs font-medium text-teal-600 dark:text-teal-300">
                                Selected
                              </span>
                            <% end %>
                          </div>
                        </button>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </:body>
        </.app_modal>

        <.app_modal
          id="chat-dashboard-payload-modal"
          show={@show_dashboard_payload_modal}
          on_cancel="close_dashboard_payload_modal"
          size="xl"
        >
          <:title>{@selected_dashboard_payload_title || "Dashboard payload"}</:title>
          <:body>
            <DashboardPayload.payload_view payload={@selected_dashboard_payload || "{}"} />
          </:body>
          <:actions>
            <button
              type="button"
              phx-click="close_dashboard_payload_modal"
              class="inline-flex items-center justify-center rounded-xl border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 transition hover:border-slate-400 hover:bg-slate-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:border-slate-500 dark:hover:bg-slate-800"
            >
              Close
            </button>
          </:actions>
        </.app_modal>

        <.app_modal
          id="chat-dashboard-preview-modal"
          show={@show_dashboard_preview_modal}
          on_cancel="close_dashboard_preview_modal"
          size="xl"
        >
          <:title>{@selected_dashboard_payload_title || "Dashboard update preview"}</:title>
          <:body>
            <p class="mb-4 text-sm text-slate-600 dark:text-slate-300">
              Review the proposed dashboard payload before applying it to the current dashboard.
            </p>
            <DashboardPayload.payload_view payload={@selected_dashboard_payload || "{}"} />
          </:body>
          <:actions>
            <button
              type="button"
              phx-click="close_dashboard_preview_modal"
              class="inline-flex items-center justify-center rounded-xl border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 transition hover:border-slate-400 hover:bg-slate-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:border-slate-500 dark:hover:bg-slate-800"
            >
              Close
            </button>
            <button
              type="button"
              phx-click="apply_dashboard_update"
              class="inline-flex items-center justify-center rounded-xl bg-teal-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-teal-700 disabled:cursor-not-allowed disabled:opacity-60"
              disabled={@pending_page_action == :dashboard_apply_update}
            >
              Apply to current dashboard
            </button>
          </:actions>
        </.app_modal>
      </div>
    </section>
    """
  end

  defp request_page_context(socket, request_id) do
    with user_id when is_binary(user_id) <- current_user_id(socket),
         tab_id when is_binary(tab_id) <- socket.assigns[:chat_tab_id] do
      ChatBus.request_page_context(user_id, tab_id, request_id, self())
    else
      _ ->
        send(self(), {:chat_context_response, request_id, socket.assigns[:current_page_context]})
    end
  end

  defp start_chat_response(socket, page_context) do
    message = socket.assigns[:pending_user_message] || ""
    base_session = socket.assigns[:session_snapshot] || socket.assigns[:session]
    parent = self()
    notify = fn event -> send(parent, {:chat_progress, event}) end
    page_context = page_context || socket.assigns[:current_page_context]

    with %Session{} = session <- base_session do
      case claim_chat_run(session) do
        :ok ->
          socket =
            socket
            |> assign(:chat_run_owner, true)
            |> assign(:chat_run_session_id, session.id)

          case maybe_append_context_message(session, page_context) do
            {:ok, session_with_context} ->
              active_source =
                resolve_active_source(
                  page_context,
                  socket.assigns[:selected_source],
                  socket.assigns[:sources]
                )

              started_at = DateTime.utc_now()

              context =
                Chat.build_context(
                  active_source,
                  socket.assigns[:sources] || [],
                  socket.assigns
                  |> Map.put(:notify, notify)
                  |> Map.put(:page_context, page_context)
                )

              optimistic_session =
                Session.append_message(session_with_context, %{role: "user", content: message})

              socket
              |> assign(:current_page_context, page_context)
              |> assign(:selected_source, active_source || socket.assigns[:selected_source])
              |> assign(:session, optimistic_session)
              |> assign_messages(optimistic_session)
              |> assign(:progress_started_at, started_at)
              |> assign(:progress_stage_started_at, started_at)
              |> assign(:progress_tick_at, started_at)
              |> ensure_progress_timer()
              |> start_async(:chat_response, fn ->
                Chat.handle_user_message(session_with_context, message, context)
              end)

            {:error, _reason} ->
              socket
              |> release_chat_run()
              |> assign(:sending, false)
              |> assign(:pending_user_message, nil)
              |> assign(:session_snapshot, nil)
              |> put_flash(:error, "Could not prepare chat request.")
          end

        {:error, :chat_run_in_progress} ->
          {socket, session} = restore_session_snapshot(socket)
          message = socket.assigns[:pending_user_message] || ""

          socket
          |> assign(:sending, false)
          |> assign(:session, session)
          |> assign_messages(session)
          |> assign(:form, to_form(%{"message" => message}))
          |> assign(:pending_user_message, nil)
          |> assign(:session_snapshot, nil)
          |> assign(:pending_context_request_id, nil)
          |> assign(:pending_page_context_override, nil)
          |> cancel_progress_timer()
          |> assign(:progress_events, [])
          |> assign(:progress_started_at, nil)
          |> assign(:progress_stage_started_at, nil)
          |> assign(:progress_tick_at, nil)
          |> put_flash(
            :error,
            "This chat is already generating a response in another tab. Wait for it to finish."
          )
      end
    else
      _ ->
        socket
        |> assign(:sending, false)
        |> assign(:pending_user_message, nil)
        |> assign(:session_snapshot, nil)
        |> put_flash(:error, "Could not prepare chat request.")
    end
  end

  defp maybe_append_context_message(%Session{} = session, nil) do
    case last_context_fingerprint(session) do
      previous when is_binary(previous) and previous != "none" ->
        SessionStore.append_message(session, %{
          role: "system",
          content: ChatPageContext.cleared_system_message()
        })

      _ ->
        {:ok, session}
    end
  end

  defp maybe_append_context_message(%Session{} = session, %{} = page_context) do
    new_fingerprint = ChatPageContext.fingerprint(page_context)
    previous_fingerprint = last_context_fingerprint(session)

    if is_binary(new_fingerprint) and new_fingerprint != previous_fingerprint do
      SessionStore.append_message(session, %{
        role: "system",
        content: ChatPageContext.system_message(page_context)
      })
    else
      {:ok, session}
    end
  end

  defp last_context_fingerprint(%Session{messages: messages}) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn message ->
      role = Map.get(message, :role, Map.get(message, "role"))
      content = Map.get(message, :content, Map.get(message, "content"))

      if role == "system" do
        ChatPageContext.extract_fingerprint(content)
      end
    end)
  end

  defp last_context_fingerprint(_), do: nil

  defp dashboard_create_attrs(socket, visualization) do
    dashboard = Map.get(visualization, :dashboard, Map.get(visualization, "dashboard", %{}))

    source =
      resolve_visualization_source(
        visualization,
        socket.assigns[:sources],
        socket.assigns[:selected_source]
      )

    if is_nil(source) do
      {:error, %{message: "No usable analytics source found for this visualization."}}
    else
      attrs =
        %{
          "name" => Map.get(dashboard, "name", Map.get(dashboard, :name, "AI Dashboard")),
          "key" =>
            Map.get(
              dashboard,
              "key",
              Map.get(
                dashboard,
                :key,
                Map.get(visualization, :metric_key, Map.get(visualization, "metric_key"))
              )
            ),
          "payload" => Map.get(dashboard, "payload", Map.get(dashboard, :payload, %{})),
          "default_timeframe" =>
            Map.get(
              dashboard,
              "default_timeframe",
              Map.get(dashboard, :default_timeframe, visualization_timeframe_value(visualization))
            ),
          "default_granularity" =>
            Map.get(
              dashboard,
              "default_granularity",
              Map.get(dashboard, :default_granularity, visualization_granularity(visualization))
            ),
          "source_type" => Source.type(source) |> Atom.to_string(),
          "source_id" => Source.id(source) |> to_string()
        }
        |> maybe_put_database_id(source)

      {:ok, attrs}
    end
  end

  defp maybe_put_database_id(attrs, source) do
    if Source.type(source) == :database do
      Map.put(attrs, "database_id", Source.id(source) |> to_string())
    else
      attrs
    end
  end

  defp resolve_visualization_source(visualization, sources, fallback_source) do
    source_ref = Map.get(visualization, :source, Map.get(visualization, "source"))
    source_from_ref(source_ref, sources) || fallback_source
  end

  defp resolve_active_source(page_context, fallback_source, sources) do
    source_ref =
      page_context
      |> query_map()
      |> Map.get("source_ref")

    source_from_ref(source_ref, sources) || fallback_source
  end

  defp source_from_ref(%{} = ref, sources) when is_list(sources) do
    type = map_get(ref, "type")
    id = map_get(ref, "id")

    Enum.find(sources, fn source ->
      to_string(Source.type(source)) == to_string(type) and
        to_string(Source.id(source)) == to_string(id)
    end)
  end

  defp source_from_ref(_, _), do: nil

  defp query_map(nil), do: %{}

  defp query_map(%{} = page_context) do
    Map.get(page_context, :query, Map.get(page_context, "query", %{}))
  end

  defp can_apply_dashboard_update?(%{} = page_context) do
    page_context
    |> Map.get(:capabilities, Map.get(page_context, "capabilities", %{}))
    |> map_get("can_apply_dashboard_update")
    |> Kernel.==(true)
  end

  defp can_apply_dashboard_update?(_), do: false

  defp current_context_summary(nil), do: nil
  defp current_context_summary(%{} = page_context), do: ChatPageContext.summary_line(page_context)

  defp displayed_source(%Source{} = source), do: source
  defp displayed_source(_), do: nil

  defp starter_prompts do
    [
      %{
        label: "Summarize the last 24h",
        message: "Summarize the last 24h for me."
      },
      %{
        label: "Show available metrics",
        message: "Give me an overview of the available metrics here."
      },
      %{
        label: "Visualize current activity",
        message: "Visualize the current activity for me."
      },
      %{
        label: "Spot unusual trends",
        message: "Analyze the current trends and tell me if anything unusual stands out."
      }
    ]
  end

  defp submit_message(socket, message) do
    message = String.trim(message || "")

    cond do
      message == "" ->
        {:noreply, socket}

      socket.assigns.sending ->
        {:noreply, socket}

      not match?(%Session{}, socket.assigns.session) ->
        {:noreply,
         put_flash(socket, :error, "Chat session is unavailable. Try resetting the chat.")}

      true ->
        request_id = UUID.generate()

        timer_ref =
          Process.send_after(
            self(),
            {:chat_context_timeout, request_id},
            @context_request_timeout_ms
          )

        in_memory_session =
          Session.append_message(socket.assigns.session, %{role: "user", content: message})

        socket =
          socket
          |> assign(:session_snapshot, socket.assigns.session)
          |> assign(:pending_user_message, message)
          |> assign(:pending_context_request_id, request_id)
          |> assign(:pending_context_timer_ref, timer_ref)
          |> assign(:pending_page_context_override, nil)
          |> cancel_progress_timer()
          |> assign(:session, in_memory_session)
          |> assign_messages(in_memory_session)
          |> assign(:form, to_form(%{"message" => ""}))
          |> assign(:sending, true)
          |> assign(:progress_events, [])
          |> assign(:progress_started_at, nil)
          |> assign(:progress_stage_started_at, nil)
          |> assign(:progress_tick_at, nil)
          |> push_event("chat_scroll_bottom", %{})

        request_page_context(socket, request_id)

        {:noreply, socket}
    end
  end

  attr :source, Source, required: true
  attr :class, :string, default: nil

  defp source_tag(assigns) do
    ~H"""
    <div class={[@class]}>
      <span class="inline-flex max-w-full items-center gap-2 rounded-full border border-slate-200 bg-slate-50 px-3 py-1 text-xs font-medium text-slate-700 shadow-sm dark:border-slate-700 dark:bg-slate-800/80 dark:text-slate-200">
        <TrifleApp.SidebarIcons.icon name={source_tag_icon(@source)} class="h-3.5 w-3.5 shrink-0" />
        <span class="truncate">{Source.display_name(@source)}</span>
      </span>
    </div>
    """
  end

  defp source_tag_icon(%Source{} = source) do
    case Source.type(source) do
      :project -> "sidebar-projects"
      _ -> "sidebar-databases"
    end
  end

  defp visualization_timeframe_value(visualization) do
    visualization
    |> Map.get(:timeframe, Map.get(visualization, "timeframe", %{}))
    |> map_get("label")
  end

  defp visualization_granularity(visualization) do
    visualization
    |> Map.get(:timeframe, Map.get(visualization, "timeframe", %{}))
    |> map_get("granularity")
  end

  defp assign_shell_defaults(socket, sources) do
    socket
    |> assign(:sources, sources)
    |> assign(:grouped_sources, group_sources(sources))
    |> assign(:selected_source, nil)
    |> assign(:session, nil)
    |> assign(:chat_session_id, nil)
    |> assign(:chat_session_topic, nil)
    |> assign(:messages, [])
    |> assign(:sending, false)
    |> assign(:progress_events, [])
    |> assign(:progress_tick_at, nil)
    |> assign(:progress_timer_ref, nil)
    |> assign(:progress_started_at, nil)
    |> assign(:progress_stage_started_at, nil)
    |> assign(:chat_run_owner, false)
    |> assign(:chat_run_session_id, nil)
    |> assign(:show_source_modal, false)
    |> assign(:can_view_dashboard_payload, admin_user?(socket.assigns[:current_user]))
    |> assign(:show_dashboard_payload_modal, false)
    |> assign(:show_dashboard_preview_modal, false)
    |> assign(:selected_dashboard_payload, nil)
    |> assign(:selected_dashboard_payload_title, nil)
    |> assign(:selected_visualization, nil)
    |> assign(:current_page_context, nil)
    |> assign(:session_page_context, nil)
    |> assign(:pending_context_request_id, nil)
    |> assign(:pending_context_timer_ref, nil)
    |> assign(:initial_context_request_id, nil)
    |> assign(:initial_context_timer_ref, nil)
    |> assign(:navigation_context_request_id, nil)
    |> assign(:navigation_context_timer_ref, nil)
    |> assign(:pending_page_context_override, nil)
    |> assign(:pending_page_action_request_id, nil)
    |> assign(:pending_page_action, nil)
    |> assign(:pending_page_action_timer_ref, nil)
    |> assign(:form, to_form(%{"message" => ""}))
  end

  defp maybe_subscribe_session(socket, %Session{id: id}) do
    if connected?(socket) do
      topic = SessionBus.session_topic(id)

      if socket.assigns[:chat_session_topic] == topic do
        socket
      else
        SessionBus.subscribe(id)

        socket
        |> assign(:chat_session_topic, topic)
        |> assign(:chat_session_id, id)
      end
    else
      assign(socket, :chat_session_id, id)
    end
  end

  defp maybe_subscribe_session(socket, _), do: socket

  defp cancel_navigation_context_request(socket) do
    case socket.assigns[:navigation_context_timer_ref] do
      nil ->
        socket
        |> assign(:navigation_context_request_id, nil)
        |> assign(:navigation_context_timer_ref, nil)

      ref ->
        Process.cancel_timer(ref)

        socket
        |> assign(:navigation_context_request_id, nil)
        |> assign(:navigation_context_timer_ref, nil)
    end
  end

  defp cancel_initial_context_request(socket) do
    case socket.assigns[:initial_context_timer_ref] do
      nil ->
        socket
        |> assign(:initial_context_request_id, nil)
        |> assign(:initial_context_timer_ref, nil)

      ref ->
        Process.cancel_timer(ref)

        socket
        |> assign(:initial_context_request_id, nil)
        |> assign(:initial_context_timer_ref, nil)
    end
  end

  defp cancel_pending_page_action_request(socket) do
    case socket.assigns[:pending_page_action_timer_ref] do
      nil ->
        socket
        |> assign(:pending_page_action_request_id, nil)
        |> assign(:pending_page_action, nil)
        |> assign(:pending_page_action_timer_ref, nil)

      ref ->
        Process.cancel_timer(ref)

        socket
        |> assign(:pending_page_action_request_id, nil)
        |> assign(:pending_page_action, nil)
        |> assign(:pending_page_action_timer_ref, nil)
    end
  end

  defp maybe_request_initial_context(socket) do
    cond do
      not connected?(socket) ->
        socket

      socket.assigns[:current_page_context] ->
        socket

      socket.assigns[:initial_context_request_id] ->
        socket

      not is_binary(current_user_id(socket)) ->
        socket

      not is_binary(socket.assigns[:chat_tab_id]) ->
        socket

      true ->
        request_id = UUID.generate()

        timer_ref =
          Process.send_after(
            self(),
            {:initial_chat_context_timeout, request_id},
            @context_request_timeout_ms + @initial_context_request_delay_ms
          )

        Process.send_after(
          self(),
          {:request_initial_chat_context, request_id},
          @initial_context_request_delay_ms
        )

        socket
        |> assign(:initial_context_request_id, request_id)
        |> assign(:initial_context_timer_ref, timer_ref)
    end
  end

  defp handle_progress_event(socket, type, payload) do
    now = DateTime.utc_now()
    normalized_type = normalize_progress_type(type)
    normalized_payload = normalize_progress_payload(payload)
    text = Progress.text(type, normalized_payload)

    cond do
      is_nil(text) ->
        {:noreply, socket}

      normalized_type == "resume" ->
        socket =
          socket
          |> update(:progress_events, fn events ->
            events
            |> Enum.reject(&resume_event?/1)
            |> Kernel.++([
              build_progress_entry(
                normalized_type,
                normalized_payload,
                text,
                started_at: nil,
                display_elapsed: false
              )
            ])
          end)
          |> assign(:progress_tick_at, now)
          |> ensure_progress_timer()
          |> push_event("chat_scroll_bottom", %{})

        {:noreply, socket}

      true ->
        socket =
          handle_non_resume_progress(socket, normalized_type, normalized_payload, text, now)

        {:noreply, socket}
    end
  end

  defp handle_non_resume_progress(socket, type, payload, text, now) do
    events = socket.assigns[:progress_events] || []

    case active_event_with_index(events) do
      {event, idx} ->
        if normalize_progress_type(Map.get(event, :type)) == type do
          updated_event =
            event
            |> Map.put(:payload, payload)
            |> Map.put(:text, text)

          updated_events = List.replace_at(events, idx, updated_event)
          stage_start = event[:started_at] || socket.assigns[:progress_stage_started_at] || now

          socket =
            socket
            |> assign(:progress_events, updated_events)
            |> assign(:progress_tick_at, now)
            |> assign(:progress_stage_started_at, stage_start)
            |> ensure_progress_timer()
            |> push_event("chat_scroll_bottom", %{})

          persist_progress(socket)
        else
          start_new_progress_stage(socket, events, type, payload, text, now)
        end

      _ ->
        start_new_progress_stage(socket, events, type, payload, text, now)
    end
  end

  defp start_new_progress_stage(socket, events, type, payload, text, now) do
    started_at = now

    entry =
      build_progress_entry(
        type,
        payload,
        text,
        started_at: started_at,
        display_elapsed: true
      )

    updated_events =
      events
      |> finish_last_progress_event(now)
      |> Kernel.++([entry])

    socket =
      socket
      |> assign(:progress_events, updated_events)
      |> assign(:progress_tick_at, now)
      |> assign(:progress_stage_started_at, started_at)
      |> ensure_progress_timer()
      |> push_event("chat_scroll_bottom", %{})

    persist_progress(socket)
  end

  defp maybe_resume_pending(socket) do
    session = socket.assigns[:session]
    page_context = socket.assigns[:current_page_context] || socket.assigns[:session_page_context]

    if match?(%Session{}, session) and Chat.pending?(session) do
      cond do
        is_nil(page_context) and socket.assigns[:initial_context_request_id] ->
          socket

        true ->
          now = DateTime.utc_now()
          {rehydrated_events, stage_start} = rehydrate_progress_events(session)

          started_at =
            session.pending_started_at ||
              earliest_started_at(rehydrated_events) ||
              latest_message_created_at(session) ||
              now

          socket =
            socket
            |> assign(:sending, true)
            |> assign(
              :progress_events,
              ensure_pending_progress_visible(rehydrated_events, started_at)
            )
            |> assign(:progress_started_at, started_at)
            |> assign(:progress_stage_started_at, stage_start || started_at)
            |> assign(:progress_tick_at, now)
            |> ensure_progress_timer()

          case claim_chat_run(session) do
            :ok ->
              parent = self()
              notify = fn event -> send(parent, {:chat_progress, event}) end

              active_source =
                resolve_active_source(
                  page_context,
                  socket.assigns[:selected_source],
                  socket.assigns[:sources]
                )

              context =
                Chat.build_context(
                  active_source,
                  socket.assigns[:sources] || [],
                  socket.assigns
                  |> Map.put(:notify, notify)
                  |> Map.put(:page_context, page_context)
                )

              socket
              |> assign(:chat_run_owner, true)
              |> assign(:chat_run_session_id, session.id)
              |> start_async(:chat_response, fn -> Chat.resume_pending(session, context) end)

            {:error, :chat_run_in_progress} ->
              socket
          end
      end
    else
      socket
      |> release_chat_run()
      |> cancel_progress_timer()
      |> assign(:sending, false)
      |> assign(:progress_events, [])
      |> assign(:progress_started_at, nil)
      |> assign(:progress_stage_started_at, nil)
      |> assign(:progress_tick_at, nil)
    end
  end

  defp persist_progress(socket) do
    with %Session{} = session <- socket.assigns[:session],
         events when is_list(events) <- socket.assigns[:progress_events] do
      persisted_events = build_persisted_events(events)

      case SessionStore.set_progress_events(session, persisted_events) do
        {:ok, updated_session} ->
          assign(socket, :session, updated_session)

        {:error, _reason} ->
          socket
      end
    else
      _ -> socket
    end
  end

  defp build_persisted_events(events) do
    events
    |> Enum.filter(&persistable_progress_event?/1)
    |> Enum.map(fn event ->
      %{
        id: Map.get(event, :id),
        type: Map.get(event, :type, "unknown"),
        payload: Map.get(event, :payload, %{}),
        text: Map.get(event, :text),
        started_at: Map.get(event, :started_at),
        finished_at: Map.get(event, :finished_at),
        display: Map.get(event, :display_elapsed, true)
      }
    end)
  end

  defp persistable_progress_event?(%{type: type}) do
    normalize_progress_type(type) != "resume"
  end

  defp persistable_progress_event?(_), do: true

  defp rehydrate_progress_events(%Session{} = session) do
    events =
      session.progress_events
      |> Enum.reject(&persisted_resume_event?/1)
      |> Enum.map(fn event ->
        payload = normalize_progress_payload(Map.get(event, :payload, %{}))
        text = Map.get(event, :text) || Progress.text(Map.get(event, :type), payload)
        started_at = Map.get(event, :started_at)
        finished_at = Map.get(event, :finished_at)
        display = Map.get(event, :display, true)

        %{
          id: Map.get(event, :id) || UUID.generate(),
          type: Map.get(event, :type, "unknown"),
          payload: payload,
          text: text,
          inserted_at: started_at,
          started_at: started_at,
          finished_at: finished_at,
          display_elapsed: display
        }
      end)

    stage_start =
      events
      |> Enum.reverse()
      |> Enum.find_value(fn
        %{display_elapsed: true, finished_at: nil, started_at: %DateTime{} = start} -> start
        _ -> nil
      end)

    {events, stage_start}
  end

  defp earliest_started_at(events) when is_list(events) do
    events
    |> Enum.map(&Map.get(&1, :started_at))
    |> Enum.filter(&match?(%DateTime{}, &1))
    |> Enum.min_by(&DateTime.to_unix(&1, :second), fn -> nil end)
  end

  defp earliest_started_at(_), do: nil

  defp sync_progress_from_session(socket, %Session{} = session) do
    owner_for_session? =
      socket.assigns[:chat_run_owner] and socket.assigns[:chat_run_session_id] == session.id and
        socket.assigns[:sending]

    if owner_for_session? do
      socket
    else
      now = DateTime.utc_now()
      {events, stage_start} = rehydrate_progress_events(session)

      if Chat.pending?(session) do
        started_at =
          session.pending_started_at ||
            earliest_started_at(events) ||
            latest_message_created_at(session) ||
            now

        visible_events = ensure_pending_progress_visible(events, started_at)

        socket
        |> assign(:sending, true)
        |> assign(:progress_events, visible_events)
        |> assign(:progress_started_at, started_at)
        |> assign(:progress_stage_started_at, stage_start || started_at)
        |> assign(:progress_tick_at, now)
        |> ensure_progress_timer()
      else
        socket
        |> cancel_progress_timer()
        |> assign(:sending, false)
        |> assign(:progress_events, events)
        |> assign(:progress_started_at, nil)
        |> assign(:progress_stage_started_at, nil)
        |> assign(:progress_tick_at, nil)
      end
    end
  end

  defp latest_message_created_at(%Session{messages: messages}) do
    messages
    |> List.last()
    |> case do
      nil ->
        nil

      message ->
        Map.get(message, :created_at) || Map.get(message, "created_at")
    end
  end

  defp latest_message_created_at(_), do: nil

  defp ensure_pending_progress_visible([], %DateTime{} = started_at) do
    [
      build_progress_entry(
        "received",
        %{},
        Progress.text(:received, %{}),
        started_at: started_at,
        display_elapsed: true
      )
    ]
  end

  defp ensure_pending_progress_visible(events, _started_at), do: events

  defp persisted_resume_event?(event) when is_map(event) do
    type = Map.get(event, :type) || Map.get(event, "type")
    normalize_progress_type(type) == "resume"
  end

  defp persisted_resume_event?(_), do: false

  defp ensure_progress_timer(socket) do
    if socket.assigns.progress_timer_ref || !active_progress?(socket.assigns.progress_events) do
      socket
    else
      ref = Process.send_after(self(), :progress_tick, 1_000)
      assign(socket, :progress_timer_ref, ref)
    end
  end

  defp cancel_progress_timer(socket) do
    case socket.assigns.progress_timer_ref do
      nil ->
        socket

      ref ->
        Process.cancel_timer(ref)
        assign(socket, :progress_timer_ref, nil)
    end
  end

  defp cancel_context_request(socket) do
    case socket.assigns[:pending_context_timer_ref] do
      nil ->
        socket
        |> assign(:pending_context_request_id, nil)
        |> assign(:pending_context_timer_ref, nil)

      ref ->
        Process.cancel_timer(ref)

        socket
        |> assign(:pending_context_request_id, nil)
        |> assign(:pending_context_timer_ref, nil)
    end
  end

  defp active_progress?(events) when is_list(events) do
    not is_nil(active_event_with_index(events))
  end

  defp active_progress?(_), do: false

  defp claim_chat_run(%Session{id: session_id}) do
    case RunnerRegistry.claim(session_id) do
      :ok -> :ok
      {:error, _pid} -> {:error, :chat_run_in_progress}
    end
  end

  defp claim_chat_run(_), do: {:error, :chat_run_in_progress}

  defp release_chat_run(socket) do
    if socket.assigns[:chat_run_owner] and is_binary(socket.assigns[:chat_run_session_id]) do
      RunnerRegistry.release(socket.assigns[:chat_run_session_id])
    end

    socket
    |> assign(:chat_run_owner, false)
    |> assign(:chat_run_session_id, nil)
  end

  defp active_event_with_index(events) when is_list(events) do
    events
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find(fn {event, _idx} -> progress_event_active?(event) end)
  end

  defp active_event_with_index(_), do: nil

  defp progress_event_active?(event) when is_map(event) do
    display = Map.get(event, :display_elapsed, true)
    finished_at = Map.get(event, :finished_at)
    started_at = Map.get(event, :started_at)

    display != false and is_nil(finished_at) and match?(%DateTime{}, started_at)
  end

  defp progress_event_active?(_), do: false

  defp build_progress_entry(type, payload, text, opts) when is_list(opts) do
    %{
      id:
        Keyword.get_lazy(opts, :id, fn ->
          "progress-" <> Integer.to_string(System.unique_integer([:positive]))
        end),
      type: type,
      payload: payload,
      text: text,
      inserted_at: DateTime.utc_now(),
      started_at: Keyword.get(opts, :started_at, DateTime.utc_now()),
      finished_at: Keyword.get(opts, :finished_at),
      display_elapsed: Keyword.get(opts, :display_elapsed, true)
    }
  end

  defp finish_last_progress_event([], _now), do: []

  defp finish_last_progress_event(events, now) when is_list(events) do
    case active_event_with_index(events) do
      {event, idx} -> List.replace_at(events, idx, maybe_finish_event(event, now))
      _ -> events
    end
  end

  defp finish_all_progress_events(socket, now) do
    update(socket, :progress_events, fn events ->
      Enum.map(events, &maybe_finish_event(&1, now))
    end)
  end

  defp maybe_finish_event(%{display_elapsed: false} = event, _now), do: event
  defp maybe_finish_event(%{finished_at: %DateTime{}} = event, _now), do: event

  defp maybe_finish_event(%{started_at: %DateTime{}} = event, %DateTime{} = now) do
    Map.put(event, :finished_at, now)
  end

  defp maybe_finish_event(event, _now), do: event

  defp append_final_duration(socket) do
    start = socket.assigns[:progress_started_at]
    now = DateTime.utc_now()

    socket =
      socket
      |> finish_all_progress_events(now)

    socket =
      case elapsed_seconds(start, now) do
        nil ->
          socket

        seconds ->
          formatted = format_duration(seconds)

          summary_event = %{
            id: "progress-summary-" <> Integer.to_string(System.unique_integer([:positive])),
            type: "summary",
            payload: %{"total" => formatted},
            text: ensure_period("Worked for #{formatted}"),
            inserted_at: now,
            started_at: nil,
            finished_at: nil,
            display_elapsed: false
          }

          update(socket, :progress_events, &(&1 ++ [summary_event]))
      end

    socket =
      socket
      |> cancel_progress_timer()
      |> assign(:progress_tick_at, nil)
      |> assign(:progress_stage_started_at, nil)

    socket = persist_progress(socket)

    socket
    |> assign(:progress_started_at, nil)
  end

  defp elapsed_seconds(nil, _finish), do: nil

  defp elapsed_seconds(%DateTime{} = start, %DateTime{} = finish) do
    DateTime.diff(finish, start, :second)
    |> max(0)
  end

  defp format_duration(nil), do: nil

  defp format_duration(seconds) when is_integer(seconds) and seconds >= 0 do
    cond do
      seconds < 60 ->
        "#{seconds}s"

      true ->
        minutes = div(seconds, 60)
        remaining = rem(seconds, 60)
        "#{minutes}m#{pad_two(remaining)}s"
    end
  end

  defp pad_two(value) when value < 10, do: "0#{value}"
  defp pad_two(value), do: Integer.to_string(value)

  defp ensure_period(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.trim_trailing(".")
    |> Kernel.<>(".")
  end

  defp ensure_period(_), do: nil

  defp normalize_progress_type(type) when is_atom(type), do: Atom.to_string(type)
  defp normalize_progress_type(type) when is_binary(type), do: type
  defp normalize_progress_type(_), do: "unknown"

  defp normalize_progress_payload(payload) when is_map(payload), do: payload
  defp normalize_progress_payload(_), do: %{}

  defp split_messages([]), do: {[], nil}

  defp split_messages(messages) when is_list(messages) do
    {last_message, rest} = List.pop_at(messages, -1)
    {rest, last_message}
  end

  defp progress_before_last?(events, sending, %{role: "assistant"})
       when is_list(events) and events != [] and sending == false do
    true
  end

  defp progress_before_last?(_events, _sending, _last_message), do: false

  defp progress_after_last?(events, sending, last_message)
       when is_list(events) and events != [] do
    not progress_before_last?(events, sending, last_message)
  end

  defp progress_after_last?(_events, _sending, _last_message), do: false

  defp reload_session(nil), do: nil

  defp reload_session(%Session{id: id}) do
    case SessionStore.get(id) do
      {:ok, session} -> session
      _ -> nil
    end
  end

  defp restore_session_snapshot(socket) do
    case {socket.assigns[:session], socket.assigns[:session_snapshot]} do
      {%Session{id: id} = current, %Session{id: id} = snapshot} ->
        case SessionStore.restore(current, snapshot) do
          {:ok, restored} ->
            {assign(socket, :session, restored), restored}

          {:error, _reason} ->
            case SessionStore.get(id) do
              {:ok, reloaded} -> {assign(socket, :session, reloaded), reloaded}
              _ -> {socket, current}
            end
        end

      {%Session{} = current, _} ->
        {socket, current}

      _ ->
        {socket, nil}
    end
  end

  defp assign_messages(socket, %Session{} = session) do
    assign(socket, :messages, build_renderable_messages(session))
  end

  defp assign_messages(socket, _), do: assign(socket, :messages, [])

  defp session_page_context(%Session{messages: messages}) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn message ->
      role = Map.get(message, :role, Map.get(message, "role"))
      content = Map.get(message, :content, Map.get(message, "content"))

      if role == "system" do
        ChatPageContext.parse_system_message(content)
      end
    end)
  end

  defp session_page_context(_), do: nil

  defp build_renderable_messages(%Session{} = session) do
    session
    |> Chat.renderable_messages()
    |> Enum.with_index()
    |> Enum.map(fn {message, idx} ->
      message
      |> decorate_visualizations()
      |> Map.put_new(:dom_id, message_dom_id(message, idx))
    end)
  end

  defp decorate_visualizations(message) do
    visuals =
      message
      |> Map.get(:visualizations, [])
      |> Enum.map(&decorate_visualization/1)

    Map.put(message, :visualizations, visuals)
  end

  defp decorate_visualization(viz) do
    dom_id =
      viz
      |> Map.get(:dom_id)
      |> case do
        nil ->
          base_id =
            viz
            |> Map.get(:id, Map.get(viz, "id"))
            |> case do
              nil -> Integer.to_string(System.unique_integer([:positive]))
              other -> to_string(other)
            end

          "chat-viz-" <> sanitize_dom_id(base_id)

        existing ->
          existing
      end

    Map.put(viz, :dom_id, dom_id)
  end

  defp message_dom_id(message, idx) do
    created_at =
      message
      |> Map.get(:created_at)
      |> case do
        %DateTime{} = dt -> DateTime.to_iso8601(dt)
        %NaiveDateTime{} = ndt -> NaiveDateTime.to_iso8601(ndt)
        other -> to_string(other || idx)
      end

    base = "#{Map.get(message, :role, "message")}-#{created_at}-#{idx}"
    sanitize_dom_id(base)
  end

  defp sanitize_dom_id(id) do
    id
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "-")
  end

  defp group_sources(sources) when is_list(sources) do
    sources
    |> Enum.reduce(%{}, fn source, acc ->
      type = Source.type(source)
      Map.update(acc, type, [source], &(&1 ++ [source]))
    end)
    |> build_source_groups()
  end

  defp group_sources(_), do: []

  defp build_source_groups(groups) when is_map(groups) do
    prioritized_types = [:database, :project]

    other_types =
      groups
      |> Map.keys()
      |> Enum.reject(&(&1 in prioritized_types))
      |> Enum.sort()

    (prioritized_types ++ other_types)
    |> Enum.reduce([], fn type, acc ->
      case Map.get(groups, type, []) do
        [] ->
          acc

        list ->
          sorted =
            list
            |> Enum.sort_by(&String.downcase(Source.display_name(&1)))

          acc ++
            [
              %{
                type: type,
                label: Source.type_label(type),
                sources: sorted
              }
            ]
      end
    end)
  end

  defp source_selected?(%Source{} = source, %Source{} = selected) do
    Source.type(source) == Source.type(selected) &&
      to_string(Source.id(source)) == to_string(Source.id(selected))
  end

  defp source_selected?(_, _), do: false

  defp source_option_classes(source, selected_source) do
    base =
      "w-full text-left rounded-xl border px-4 py-3 text-sm transition-colors focus:outline-none focus:ring-2 focus:ring-teal-500 focus:ring-offset-2 dark:focus:ring-offset-slate-900"

    if source_selected?(source, selected_source) do
      base <>
        " border-teal-500 bg-teal-50 text-teal-900 dark:border-teal-400 dark:bg-teal-500/10 dark:text-teal-100"
    else
      base <>
        " border-slate-200 bg-white text-slate-700 hover:border-teal-400 hover:text-teal-700 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:border-teal-400 dark:hover:text-teal-200"
    end
  end

  defp source_option_hint(%Source{} = source) do
    [
      Source.type_label(Source.type(source)),
      Source.time_zone(source)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" • ")
  end

  defp parse_source_ref(nil, _sources), do: nil

  defp parse_source_ref(ref, sources) do
    Enum.find(sources, fn source -> encode_source_ref(source) == ref end)
  end

  defp encode_source_ref(%Source{} = source) do
    type = source |> Source.type() |> Atom.to_string()
    id = source |> Source.id() |> to_string()
    "#{type}:#{id}"
  end

  defp current_user_id(socket) do
    case socket.assigns[:current_user] do
      %{id: id} when not is_nil(id) -> to_string(id)
      _ -> nil
    end
  end

  defp no_source_notice(assigns) do
    ~H"""
    <div class="rounded-2xl border border-dashed border-slate-300 px-4 py-4 text-sm text-slate-500 dark:border-slate-700 dark:text-slate-400">
      This page does not provide analytics context. Pick a fallback source if you want to ask about
      metrics from here.
    </div>
    """
  end

  attr :message, :map, required: true
  attr :current_user, :any
  attr :can_view_dashboard_payload, :boolean, default: false
  attr :can_apply_dashboard_update, :boolean, default: false

  defp chat_message(assigns) do
    ~H"""
    <div id={"chat-message-#{@message.dom_id}"} class={message_stack_classes(@message)}>
      <div :if={bubble_visible?(@message)} class={message_row_classes(@message)}>
        <div :if={@message.role == "user"} class="shrink-0">
          <img
            src={avatar_url(@message, @current_user)}
            alt={avatar_alt(@message)}
            class="h-8 w-8 rounded-full border border-teal-200 object-cover dark:border-teal-500/60"
            width="32"
            height="32"
          />
        </div>

        <div class={bubble_classes(@message)}>
          <div class={bubble_header_classes(@message)}>
            <span class={bubble_author_classes(@message)}>{display_role(@message.role)}</span>
            <span :if={@message.created_at} class={bubble_timestamp_classes(@message)}>
              {format_timestamp(@message.created_at)}
            </span>
          </div>

          <p :if={message_has_text?(@message)} class={bubble_text_classes(@message)}>
            {@message.content}
          </p>
        </div>
      </div>

      <div
        :if={Enum.any?(dashboard_visualizations(@message))}
        class={dashboard_block_classes(@message)}
      >
        <.chat_dashboard_visualization
          :for={viz <- dashboard_visualizations(@message)}
          message_dom_id={@message.dom_id}
          visualization={viz}
          can_view_dashboard_payload={@can_view_dashboard_payload}
          can_apply_dashboard_update={@can_apply_dashboard_update}
        />
      </div>
    </div>
    """
  end

  attr :visualization, :map, required: true
  attr :message_dom_id, :string, required: true
  attr :can_view_dashboard_payload, :boolean, default: false
  attr :can_apply_dashboard_update, :boolean, default: false

  defp chat_dashboard_visualization(assigns) do
    visualization = assigns.visualization

    assigns =
      assigns
      |> assign(:dom_id, Map.get(visualization, :dom_id))
      |> assign(
        :dashboard_render,
        dashboard_visualization_render(visualization, Map.get(visualization, :dom_id))
      )

    ~H"""
    <div class="space-y-3 rounded-2xl border border-slate-200/80 bg-white/70 p-3 shadow-sm dark:border-slate-700/70 dark:bg-slate-900/50">
      <%= if @dashboard_render do %>
        <WidgetView.grid
          dashboard={@dashboard_render.dashboard}
          stats={@dashboard_render.stats}
          print_mode={false}
          current_user={nil}
          can_edit_dashboard={false}
          is_public_access={true}
          public_token={nil}
          grid_dom_id={@dashboard_render.grid_dom_id}
          widget_export={%{type: :disabled}}
          kpi_values={@dashboard_render.dataset_maps.kpi_values}
          kpi_visuals={@dashboard_render.dataset_maps.kpi_visuals}
          timeseries={@dashboard_render.dataset_maps.timeseries}
          category={@dashboard_render.dataset_maps.category}
          table={@dashboard_render.dataset_maps.table}
          text_widgets={@dashboard_render.dataset_maps.text}
          list={@dashboard_render.dataset_maps.list}
          distribution={@dashboard_render.dataset_maps.distribution}
        />
      <% else %>
        <div class="text-xs italic text-slate-500 dark:text-slate-400">
          Could not render this dashboard snapshot.
        </div>
      <% end %>

      <div class="flex flex-wrap justify-end gap-2">
        <button
          type="button"
          phx-click="create_dashboard_from_visualization"
          phx-value-dom_id={@dom_id}
          phx-value-message_id={@message_dom_id}
          class="inline-flex items-center rounded-xl border border-slate-300 bg-white px-3 py-2 text-xs font-medium text-slate-700 transition hover:border-teal-400 hover:text-slate-900 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:border-teal-400 dark:hover:text-white"
        >
          Create dashboard
        </button>

        <button
          :if={@can_apply_dashboard_update}
          type="button"
          phx-click="preview_dashboard_update"
          phx-value-dom_id={@dom_id}
          phx-value-message_id={@message_dom_id}
          class="inline-flex items-center rounded-xl border border-teal-300 bg-teal-50 px-3 py-2 text-xs font-medium text-teal-700 transition hover:border-teal-400 hover:bg-teal-100 dark:border-teal-500/50 dark:bg-teal-500/10 dark:text-teal-200 dark:hover:bg-teal-500/20"
        >
          Preview update
        </button>

        <div :if={@can_view_dashboard_payload} class="flex justify-end">
          <DashboardPayload.payload_button
            phx-click="open_dashboard_payload"
            phx-value-dom_id={@dom_id}
            phx-value-message_id={@message_dom_id}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :events, :list, required: true
  attr :active, :boolean, default: false
  attr :tick_at, :integer, default: nil

  defp progress_events(assigns) do
    ~H"""
    <% last_id = last_event_id(@events) %>
    <div :for={event <- @events} id={event.id} class={progress_event_class(event, last_id, @active)}>
      <span class={progress_event_text_class(event, last_id, @active)}>
        {event.text}
      </span>
      <% formatted_elapsed = formatted_elapsed(event, @tick_at) %>
      <span
        :if={formatted_elapsed}
        class="ml-2 text-[11px] tracking-wide text-slate-400 dark:text-slate-500"
      >
        {formatted_elapsed}
      </span>
    </div>
    """
  end

  defp last_event_id(events) when is_list(events) do
    case active_event_with_index(events) do
      {event, _idx} -> Map.get(event, :id)
      _ -> (List.last(events) || %{}) |> Map.get(:id)
    end
  end

  defp last_event_id(_), do: nil

  defp progress_event_class(event, last_id, active) do
    base =
      "text-center text-xs italic text-slate-500 transition-colors duration-300 dark:text-slate-400"

    if active && event.id == last_id do
      base <> " text-slate-600 dark:text-slate-300"
    else
      base
    end
  end

  defp progress_event_text_class(event, last_id, true) when event.id == last_id do
    "chat-progress-wave"
  end

  defp progress_event_text_class(_event, _last_id, _active), do: ""

  defp formatted_elapsed(%{display_elapsed: false}, _tick_at), do: nil
  defp formatted_elapsed(%{started_at: nil}, _tick_at), do: nil

  defp formatted_elapsed(event, tick_at) do
    started_at = Map.get(event, :started_at)

    cond do
      not match?(%DateTime{}, started_at) ->
        nil

      match?(%DateTime{}, Map.get(event, :finished_at)) ->
        seconds = elapsed_seconds(started_at, Map.get(event, :finished_at))
        format_duration(seconds)

      match?(%DateTime{}, tick_at) ->
        seconds = elapsed_seconds(started_at, tick_at)
        format_duration(seconds)

      true ->
        seconds = elapsed_seconds(started_at, DateTime.utc_now())
        format_duration(seconds)
    end
  end

  defp resume_event?(%{type: type}) do
    normalize_progress_type(type) == "resume"
  end

  defp resume_event?(_), do: false

  defp bubble_visible?(message), do: message_has_text?(message)

  defp dashboard_visualizations(message) do
    message
    |> Map.get(:visualizations, [])
    |> Enum.filter(&(visualization_type(&1) == "dashboard"))
  end

  defp visualization_type(visualization) do
    visualization
    |> Map.get(:type, Map.get(visualization, "type"))
    |> to_string()
    |> String.downcase()
  end

  defp message_stack_classes(%{role: "user"}), do: "flex w-full flex-col items-end gap-3"
  defp message_stack_classes(_message), do: "flex w-full flex-col items-start gap-3"

  defp message_row_classes(%{role: "user"}),
    do: "flex w-full items-start justify-end gap-2.5 flex-row-reverse"

  defp message_row_classes(_message), do: "flex w-full items-start justify-start gap-2.5"

  defp dashboard_block_classes(%{role: "user"}), do: "ml-auto w-full max-w-[1100px]"
  defp dashboard_block_classes(_message), do: "mr-auto w-full max-w-[1100px]"

  defp bubble_classes(%{role: "assistant"}) do
    "mr-auto flex w-full max-w-[88%] flex-col rounded-2xl rounded-es-none border border-slate-200 bg-white px-4 pb-3 pt-3 leading-1.5 shadow-sm dark:border-slate-700 dark:bg-slate-800/70"
  end

  defp bubble_classes(%{role: "user"}) do
    "ml-auto flex w-full max-w-[82%] flex-col rounded-2xl rounded-ee-none bg-teal-600 px-4 pb-3 pt-3 text-white shadow"
  end

  defp bubble_header_classes(%{role: "assistant"}),
    do: "flex items-center gap-2 text-xs text-slate-500 dark:text-slate-300"

  defp bubble_header_classes(%{role: "user"}),
    do: "flex items-center justify-end gap-2 text-xs text-white"

  defp bubble_author_classes(%{role: "assistant"}),
    do: "font-semibold text-slate-700 dark:text-slate-100"

  defp bubble_author_classes(%{role: "user"}), do: "font-semibold text-white"

  defp bubble_text_classes(%{role: "assistant"}),
    do: "whitespace-pre-line text-sm leading-5 text-slate-800 dark:text-slate-100"

  defp bubble_text_classes(%{role: "user"}),
    do: "whitespace-pre-line text-right text-sm leading-5 text-white"

  defp bubble_timestamp_classes(%{role: "user"}), do: "text-xs text-white/80"
  defp bubble_timestamp_classes(_), do: "text-xs text-slate-400 dark:text-slate-500"

  defp display_role("user"), do: "You"
  defp display_role("assistant"), do: "Baker Agent"
  defp display_role(role), do: role

  defp avatar_url(message = %{role: "user"}, current_user) do
    message
    |> message_author()
    |> user_avatar_asset() ||
      current_user
      |> user_avatar_asset() ||
      identicon_data_url(current_user || message, "Y", "#0f766e")
  end

  defp avatar_url(message, _current_user) do
    message
    |> message_author()
    |> user_avatar_asset() ||
      identicon_data_url("baker-agent", "B", "#7c3aed")
  end

  defp avatar_alt(%{role: "assistant"}), do: "Baker Agent avatar"
  defp avatar_alt(_), do: "Your avatar"

  defp message_has_text?(message) do
    content = Map.get(message, :content)

    cond do
      is_binary(content) -> String.trim(content) != ""
      true -> false
    end
  end

  defp dashboard_visualization_render(visualization, dom_id) do
    case InlineDashboard.render_state(visualization) do
      {:ok, %{dashboard: dashboard, stats: stats, dataset_maps: dataset_maps}} ->
        %{
          dashboard: dashboard,
          stats: stats,
          grid_dom_id: "#{dom_id}-grid",
          dataset_maps: dataset_maps
        }

      {:error, _reason} ->
        nil
    end
  end

  defp maybe_flash_tool_error(socket, %{role: "tool", content: content})
       when is_binary(content) and content != "" do
    put_flash(socket, :error, content)
  end

  defp maybe_flash_tool_error(socket, _), do: socket

  defp format_error(%{error: message}), do: message
  defp format_error(%{status: _status, error: message}), do: message
  defp format_error(%{message: message}) when is_binary(message), do: message
  defp format_error(other), do: inspect(other)

  defp map_get(nil, _key), do: nil

  defp map_get(map, key) when is_map(map) do
    Map.get(map, key) ||
      Map.get(map, to_string(key)) ||
      map_get_existing_atom(map, key)
  end

  defp map_get_existing_atom(map, key) when is_map(map) and is_binary(key) do
    try do
      Map.get(map, String.to_existing_atom(key))
    rescue
      ArgumentError -> nil
    end
  end

  defp map_get_existing_atom(_map, _key), do: nil

  defp clear_current_page_context(socket) do
    assign(socket, :current_page_context, nil)
  end

  defp message_author(message) when is_map(message) do
    Map.get(message, :author) || Map.get(message, "author")
  end

  defp message_author(_), do: nil

  defp user_avatar_asset(entity) when is_map(entity) do
    [:avatar, :avatar_url, "avatar", "avatar_url"]
    |> Enum.find_value(fn key ->
      case Map.get(entity, key) do
        value when is_binary(value) and value != "" -> value
        _ -> nil
      end
    end)
  end

  defp user_avatar_asset(_), do: nil

  defp identicon_data_url(seed, fallback_label, background) do
    label = avatar_label(seed, fallback_label)
    seed_value = avatar_seed(seed, fallback_label)
    background = avatar_background(seed_value, background)
    foreground = "#ffffff"

    svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" role="img" aria-label="#{label}">
      <rect width="64" height="64" rx="20" fill="#{background}" />
      <text x="32" y="38" text-anchor="middle" font-size="26" font-family="Inter,Arial,sans-serif" fill="#{foreground}" font-weight="700">
        #{label}
      </text>
    </svg>
    """

    "data:image/svg+xml;base64," <> Base.encode64(svg)
  end

  defp avatar_seed(%{} = entity, fallback_label) do
    Map.get(entity, :id) ||
      Map.get(entity, "id") ||
      Map.get(entity, :name) ||
      Map.get(entity, "name") ||
      fallback_label
      |> to_string()
  end

  defp avatar_seed(seed, _fallback_label), do: to_string(seed)

  defp avatar_label(%{} = entity, fallback_label) do
    entity
    |> Map.get(:name, Map.get(entity, "name", fallback_label))
    |> to_string()
    |> String.trim()
    |> String.first()
    |> case do
      nil -> fallback_label
      value -> String.upcase(value)
    end
  end

  defp avatar_label(_seed, fallback_label), do: fallback_label

  defp avatar_background(seed_value, fallback) do
    case Base.encode16(:crypto.hash(:sha256, to_string(seed_value)), case: :lower) do
      <<r::binary-size(2), g::binary-size(2), b::binary-size(2), _::binary>> ->
        "#" <> r <> g <> b

      _ ->
        fallback
    end
  end

  defp admin_user?(%{is_admin: true}), do: true
  defp admin_user?(_), do: false

  defp format_timestamp(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%H:%M")
  rescue
    _ -> ""
  end

  defp format_timestamp(_), do: ""

  defp find_dashboard_visualization(messages, dom_id, message_id)
       when is_binary(dom_id) and is_binary(message_id) do
    messages
    |> Enum.find(fn message -> Map.get(message, :dom_id) == message_id end)
    |> case do
      nil ->
        nil

      message ->
        message
        |> dashboard_visualizations()
        |> Enum.find(fn visualization -> Map.get(visualization, :dom_id) == dom_id end)
    end
  end

  defp find_dashboard_visualization(_messages, _dom_id, _message_id), do: nil

  defp dashboard_payload_title(visualization) do
    case Map.get(visualization, :title, Map.get(visualization, "title")) do
      title when is_binary(title) and title != "" -> "#{title} payload"
      _ -> "Dashboard payload"
    end
  end
end
