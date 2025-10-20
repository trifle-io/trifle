defmodule TrifleApp.ChatLive do
  use TrifleApp, :live_view

  alias Ecto.UUID
  alias Trifle.Chat
  alias Trifle.Chat.Progress
  alias Trifle.Chat.Session
  alias Trifle.Chat.SessionStore
  alias Trifle.Stats.Source

  @impl true
  def mount(_params, _session, %{assigns: %{current_membership: nil}} = socket) do
    {:ok, redirect(socket, to: ~p"/organization/profile")}
  end

  def mount(_params, _session, socket) do
    sources =
      socket.assigns.current_membership
      |> Source.list_for_membership()

    selected_source = List.first(sources)

    socket =
      socket
      |> assign(:page_title, "Trifle AI")
      |> assign(:breadcrumb_links, ["Trifle AI"])
      |> assign(:sources, sources)
      |> assign(:selected_source, selected_source)
      |> assign(:session, nil)
      |> assign(:messages, [])
      |> assign(:sending, false)
      |> assign(:progress_events, [])
      |> assign(:progress_tick_at, nil)
      |> assign(:progress_timer_ref, nil)
      |> assign(:progress_started_at, nil)
      |> assign(:progress_stage_started_at, nil)
      |> assign(:form, to_form(%{"message" => ""}))

    {:ok, init_session(socket, selected_source)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    with {:ok, source} <- source_from_params(params, socket.assigns.sources) do
      {:noreply, init_session(socket, source)}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("send_message", %{"chat" => %{"message" => message}}, socket) do
    message = String.trim(message || "")

    cond do
      socket.assigns.selected_source == nil ->
        {:noreply, put_flash(socket, :error, "Select an analytics source first.")}

      not match?(%Session{}, socket.assigns.session) ->
        {:noreply,
         put_flash(socket, :error, "Chat session is unavailable. Try resetting the chat.")}

      message == "" ->
        {:noreply, socket}

      socket.assigns.sending ->
        {:noreply, socket}

      true ->
        session = socket.assigns.session
        parent = self()
        notify = fn event -> send(parent, {:chat_progress, event}) end
        started_at = DateTime.utc_now()

        context =
          Chat.build_context(
            socket.assigns.selected_source,
            socket.assigns.sources,
            Map.put(socket.assigns, :notify, notify)
          )

        in_memory_session = Session.append_message(session, %{role: "user", content: message})

        socket =
          socket
          |> cancel_progress_timer()
          |> assign(:session, in_memory_session)
          |> assign(:messages, Chat.renderable_messages(in_memory_session))
          |> assign(:form, to_form(%{"message" => ""}))
          |> assign(:sending, true)
          |> assign(:progress_events, [])
          |> assign(:progress_started_at, started_at)
          |> assign(:progress_stage_started_at, started_at)
          |> assign(:progress_tick_at, started_at)
          |> push_event("chat_scroll_bottom", %{})
          |> start_async(:chat_response, fn ->
            Chat.handle_user_message(session, message, context)
          end)

        {:noreply, socket}
    end
  end

  def handle_event("reset_chat", _params, socket) do
    case socket.assigns.session do
      %Session{} = session ->
        case Chat.reset(session) do
          {:ok, reset_session} ->
            {:noreply,
             socket
             |> cancel_progress_timer()
             |> assign(:session, reset_session)
             |> assign(:messages, [])
             |> assign(:progress_events, [])
             |> assign(:progress_started_at, nil)
             |> assign(:progress_stage_started_at, nil)
             |> assign(:progress_tick_at, nil)
             |> put_flash(:info, "Chat cleared.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Could not reset chat: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("change_source", %{"source" => source_ref}, socket) do
    case parse_source_ref(source_ref, socket.assigns.sources) do
      nil ->
        {:noreply, put_flash(socket, :error, "Unknown analytics source.")}

      source ->
        {:noreply,
         socket
         |> push_patch(to: ~p"/chat?source=#{encode_source_ref(source)}")}
    end
  end

  @impl true
  def handle_async(:chat_response, {:ok, {:ok, session, latest_message}}, socket) do
    socket =
      socket
      |> assign(:session, session)
      |> assign(:messages, Chat.renderable_messages(session))
      |> assign(:sending, false)
      |> maybe_flash_tool_error(latest_message)
      |> append_final_duration()

    {:noreply, socket |> push_event("chat_scroll_bottom", %{})}
  end

  def handle_async(:chat_response, {:ok, {:error, %{status: :missing_api_key} = error}}, socket) do
    socket =
      socket
      |> assign(:sending, false)
      |> assign(:session, reload_session(socket.assigns.session))
      |> put_flash(:error, format_error(error))
      |> append_final_duration()

    {:noreply, socket}
  end

  def handle_async(:chat_response, {:ok, {:error, reason}}, socket) do
    socket =
      socket
      |> assign(:sending, false)
      |> assign(:session, reload_session(socket.assigns.session))
      |> put_flash(:error, format_error(reason))
      |> append_final_duration()

    {:noreply, socket}
  end

  def handle_async(:chat_response, {:exit, reason}, socket) do
    socket =
      socket
      |> assign(:sending, false)
      |> put_flash(:error, "Chat process crashed: #{inspect(reason)}")
      |> append_final_duration()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:chat_progress, {:progress, type}}, socket) do
    handle_progress_event(socket, type, %{})
  end

  def handle_info({:chat_progress, {:progress, type, payload}}, socket) do
    handle_progress_event(socket, type, payload)
  end

  def handle_info({:chat_progress, _other}, socket), do: {:noreply, socket}

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

  def handle_info(_message, socket), do: {:noreply, socket}

  defp init_session(socket, nil) do
    socket
    |> cancel_progress_timer()
    |> assign(:selected_source, nil)
    |> assign(:session, nil)
    |> assign(:messages, [])
    |> assign(:progress_events, [])
    |> assign(:progress_tick_at, nil)
    |> assign(:progress_timer_ref, nil)
    |> assign(:progress_started_at, nil)
    |> assign(:progress_stage_started_at, nil)
    |> assign(:sending, false)
  end

  defp init_session(socket, %Source{} = source) do
    with {:ok, session} <-
           Chat.ensure_session(
             socket.assigns.current_user,
             socket.assigns.current_membership,
             source
           ) do
      socket
      |> cancel_progress_timer()
      |> assign(:selected_source, source)
      |> assign(:session, session)
      |> assign(:messages, Chat.renderable_messages(session))
      |> assign(:progress_events, [])
      |> assign(:progress_tick_at, nil)
      |> assign(:progress_timer_ref, nil)
      |> assign(:progress_started_at, nil)
      |> assign(:progress_stage_started_at, nil)
      |> maybe_resume_pending()
    else
      {:error, error} ->
        socket
        |> cancel_progress_timer()
        |> assign(:selected_source, source)
        |> assign(:session, nil)
        |> assign(:messages, [])
        |> assign(:progress_events, [])
        |> assign(:progress_tick_at, nil)
        |> assign(:progress_timer_ref, nil)
        |> assign(:progress_started_at, nil)
        |> assign(:progress_stage_started_at, nil)
        |> assign(:sending, false)
        |> put_flash(:error, "Unable to load chat session: #{format_error(error)}")
    end
  end

  defp maybe_resume_pending(socket) do
    session = socket.assigns[:session]

    if match?(%Session{}, session) and Chat.pending?(session) do
      parent = self()
      notify = fn event -> send(parent, {:chat_progress, event}) end

      now = DateTime.utc_now()
      {rehydrated_events, stage_start} = rehydrate_progress_events(session)

      started_at =
        session.pending_started_at ||
          earliest_started_at(rehydrated_events) ||
          latest_message_created_at(session) ||
          now

      context =
        Chat.build_context(
          socket.assigns[:selected_source],
          socket.assigns[:sources],
          Map.put(socket.assigns, :notify, notify)
        )

      socket
      |> assign(:sending, true)
      |> assign(:progress_events, rehydrated_events)
      |> assign(:progress_started_at, started_at)
      |> assign(:progress_stage_started_at, stage_start || started_at)
      |> assign(:progress_tick_at, now)
      |> ensure_progress_timer()
      |> start_async(:chat_response, fn -> Chat.resume_pending(session, context) end)
    else
      socket
      |> cancel_progress_timer()
      |> assign(:sending, false)
      |> assign(:progress_events, [])
      |> assign(:progress_started_at, nil)
      |> assign(:progress_stage_started_at, nil)
      |> assign(:progress_tick_at, nil)
    end
  end

  defp source_from_params(%{"source" => ref}, sources) do
    case parse_source_ref(ref, sources) do
      nil -> {:error, :not_found}
      source -> {:ok, source}
    end
  end

  defp source_from_params(_params, _sources), do: {:error, :no_change}

  defp parse_source_ref(nil, _sources), do: nil

  defp parse_source_ref(ref, sources) do
    sources
    |> Enum.find(fn source ->
      encode_source_ref(source) == ref
    end)
  end

  defp encode_source_ref(%Source{} = source) do
    type = source |> Source.type() |> Atom.to_string()
    id = source |> Source.id() |> to_string()
    "#{type}:#{id}"
  end

  defp reload_session(nil), do: nil

  defp reload_session(%Session{id: id}) do
    case SessionStore.get(id) do
      {:ok, session} -> session
      _ -> nil
    end
  end

  defp format_error(%{error: message}), do: message
  defp format_error(%{status: _status, error: message}), do: message
  defp format_error(%{message: message}) when is_binary(message), do: message
  defp format_error(other), do: inspect(other)

  defp maybe_flash_tool_error(socket, %{role: "tool", content: content})
       when is_binary(content) and content != "" do
    put_flash(socket, :error, content)
  end

  defp maybe_flash_tool_error(socket, _), do: socket

  defp build_progress_entry(type, payload, text, opts \\ []) when is_list(opts) do
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

  defp resume_event?(%{type: type}) do
    normalize_progress_type(type) == "resume"
  end

  defp resume_event?(_), do: false

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

  defp last_event_id(events) when is_list(events) do
    case active_event_with_index(events) do
      {event, _idx} -> Map.get(event, :id)
      _ -> (List.last(events) || %{}) |> Map.get(:id)
    end
  end

  defp last_event_id(_), do: nil

  defp progress_event_class(event, last_id, active) do
    base =
      "text-xs text-slate-500 dark:text-slate-400 text-center italic transition-colors duration-300"

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

  defp active_progress?(events) when is_list(events) do
    not is_nil(active_event_with_index(events))
  end

  defp active_progress?(_), do: false

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

  defp progress_text({:progress, type, payload}) do
    Progress.text(type, normalize_progress_payload(payload))
  end

  defp progress_text({:progress, type}) do
    Progress.text(type, %{})
  end

  defp progress_text(_event), do: nil

  defp persist_progress(socket) do
    with {:ok, socket, session} <- ensure_session_for_progress(socket),
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

  defp ensure_session_for_progress(%{assigns: %{session: %Session{} = session}} = socket) do
    {:ok, socket, session}
  end

  defp ensure_session_for_progress(socket), do: {:error, socket}

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

  defp persisted_resume_event?(event) when is_map(event) do
    type = Map.get(event, :type) || Map.get(event, "type")
    normalize_progress_type(type) == "resume"
  end

  defp persisted_resume_event?(_), do: false

  defp ensure_period(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.trim_trailing(".")
    |> Kernel.<>(".")
  end

  defp normalize_progress_type(type) when is_atom(type), do: Atom.to_string(type)
  defp normalize_progress_type(type) when is_binary(type), do: type
  defp normalize_progress_type(_), do: "unknown"

  defp normalize_progress_payload(payload) when is_map(payload), do: payload
  defp normalize_progress_payload(_), do: %{}

  defp ensure_period(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 h-full">
      <div class="flex items-center justify-between gap-3">
        <.source_selector sources={@sources} selected={@selected_source} change="change_source" />
        <button
          type="button"
          phx-click="reset_chat"
          class="inline-flex items-center gap-2 text-sm text-slate-600 dark:text-slate-300 hover:text-slate-900 dark:hover:text-white border border-teal-400 dark:border-teal-500 px-3 py-1 rounded disabled:opacity-50"
          disabled={@session == nil}
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
            class="size-5"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M20.25 8.511c.884.284 1.5 1.128 1.5 2.097v4.286c0 1.136-.847 2.1-1.98 2.193-.34.027-.68.052-1.02.072v3.091l-3-3c-1.354 0-2.694-.055-4.02-.163a2.115 2.115 0 0 1-.825-.242m9.345-8.334a2.126 2.126 0 0 0-.476-.095 48.64 48.64 0 0 0-8.048 0c-1.131.094-1.976 1.057-1.976 2.192v4.286c0 .837.46 1.58 1.155 1.951m9.345-8.334V6.637c0-1.621-1.152-3.026-2.76-3.235A48.455 48.455 0 0 0 11.25 3c-2.115 0-4.198.137-6.24.402-1.608.209-2.76 1.614-2.76 3.235v6.226c0 1.621 1.152 3.026 2.76 3.235.577.075 1.157.14 1.74.194V21l4.155-4.155"
            />
          </svg>
          <span class="hidden sm:inline">New Chat</span>
        </button>
      </div>

      <div
        id="chat-messages"
        class="flex-1 overflow-y-auto rounded p-4 space-y-4"
        data-chat-container
        phx-hook="ChatScroll"
      >
        <.no_source_notice :if={@selected_source == nil} />

        <% {messages_without_last, last_message} = split_messages(@messages) %>

        <.chat_message
          :for={message <- messages_without_last}
          message={message}
          current_user={@current_user}
        />

        <.progress_events
          :if={progress_before_last?(@progress_events, @sending, last_message)}
          events={@progress_events}
          active={@sending}
          tick_at={@progress_tick_at}
        />

        <.chat_message :if={last_message} message={last_message} current_user={@current_user} />

        <.progress_events
          :if={progress_after_last?(@progress_events, @sending, last_message)}
          events={@progress_events}
          active={@sending}
          tick_at={@progress_tick_at}
        />

        <div
          :if={@messages == [] and @selected_source}
          class="text-sm text-slate-500 dark:text-slate-400"
        >
          Start the conversation – ask about metrics for <span class="font-semibold"><%= Source.display_name(@selected_source) %></span>.
        </div>
      </div>

      <.simple_form for={@form} phx-submit="send_message" class="mt-auto sticky bottom-0 pt-2 pb-2">
        <div class="relative overflow-hidden rounded-2xl border border-transparent dark:border-slate-700 focus-within:border-teal-500/60 dark:focus-within:border-teal-400 bg-white/60 dark:bg-slate-900/40 backdrop-blur-xl shadow-lg dark:shadow-none">
          <div class="flex items-end">
            <textarea
              name="chat[message]"
              rows="3"
              placeholder="Ask me about your metrics..."
              class="flex-1 bg-transparent text-slate-900 dark:text-slate-100 text-sm px-4 py-4 resize-none border-0 focus:ring-0 focus:border-0"
              required
              disabled={@selected_source == nil or @sending}
            ><%= Phoenix.HTML.Form.input_value(@form, :message) %></textarea>

            <button
              type="submit"
              class="inline-flex items-center justify-center bg-teal-600 hover:bg-teal-700 text-white px-4 py-3 mr-3 mb-3 rounded-xl text-sm disabled:opacity-60 disabled:cursor-not-allowed shadow-sm"
              disabled={@selected_source == nil or @sending}
            >
              <%= if @sending do %>
                <span class="animate-spin h-4 w-4 border-2 border-white border-t-transparent rounded-full">
                </span>
              <% else %>
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="size-5"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M6 12 3.269 3.125A59.769 59.769 0 0 1 21.485 12 59.768 59.768 0 0 1 3.27 20.875L5.999 12Zm0 0h7.5"
                  />
                </svg>
              <% end %>
            </button>
          </div>
        </div>
      </.simple_form>
    </div>
    """
  end

  attr :sources, :list, required: true
  attr :selected, Source
  attr :change, :string, default: "change_source"

  defp source_selector(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <label class="text-sm text-slate-600 dark:text-slate-300">Source</label>
      <select
        name="source"
        phx-change={@change}
        class="text-sm border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 text-slate-900 dark:text-slate-100 rounded px-3 py-2"
      >
        <option :if={Enum.empty?(@sources)} value="">No analytics sources</option>
        <option
          :for={source <- @sources}
          value={encode_source_ref(source)}
          selected={source == @selected}
        >
          {Source.display_name(source)}
        </option>
      </select>
    </div>
    """
  end

  defp no_source_notice(assigns) do
    ~H"""
    <div class="text-sm text-slate-500 dark:text-slate-400">
      Add an analytics database or project to start chatting. Once a source is available you can
      ask about timeframes, key metrics, and their summaries.
    </div>
    """
  end

  attr :message, :map, required: true
  attr :current_user, :any

  defp chat_message(assigns) do
    ~H"""
    <div class={message_container_classes(@message)}>
      <div :if={@message.role == "user"} class="flex-shrink-0">
        <img
          src={avatar_url(@message, @current_user)}
          alt={avatar_alt(@message)}
          class="w-8 h-8 rounded-full border border-teal-200 dark:border-teal-500/60 object-cover"
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

        <p class={bubble_text_classes(@message)}>
          {@message.content}
        </p>
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

  defp display_role("user"), do: "You"
  defp display_role("assistant"), do: "Trifle AI"
  defp display_role(role), do: role

  defp message_container_classes(%{role: "user"}) do
    "flex w-full items-start gap-2.5 justify-end flex-row-reverse"
  end

  defp message_container_classes(_message) do
    "flex w-full items-start gap-2.5 justify-start"
  end

  defp bubble_classes(%{role: "assistant"}) do
    "flex flex-col w-full max-w-[60%] mr-auto leading-1.5 px-4 pb-3 pt-3 border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800/70 rounded-2xl rounded-es-none shadow-sm"
  end

  defp bubble_classes(%{role: "user"}) do
    "flex flex-col w-full max-w-[60%] ml-auto leading-1.5 px-4 pb-3 pt-3 bg-teal-600 text-white rounded-2xl rounded-ee-none shadow"
  end

  defp bubble_header_classes(%{role: "assistant"}) do
    "flex items-center gap-2 text-xs text-slate-500 dark:text-slate-300"
  end

  defp bubble_header_classes(%{role: "user"}) do
    "flex items-center justify-end gap-2 text-xs text-white"
  end

  defp bubble_author_classes(%{role: "assistant"}),
    do: "font-semibold text-slate-700 dark:text-slate-100"

  defp bubble_author_classes(%{role: "user"}), do: "font-semibold text-white"

  defp bubble_text_classes(%{role: "assistant"}) do
    "text-sm text-slate-800 dark:text-slate-100 whitespace-pre-line leading-snug"
  end

  defp bubble_text_classes(%{role: "user"}) do
    "text-sm text-white whitespace-pre-line text-right leading-snug"
  end

  defp bubble_timestamp_classes(%{role: "user"}) do
    "text-xs text-white/80"
  end

  defp bubble_timestamp_classes(_), do: "text-xs text-slate-400 dark:text-slate-500"

  defp avatar_url(%{role: "user"}, current_user) do
    email = current_user && current_user.email
    gravatar_url(email, 64)
  end

  defp avatar_url(_message, _current_user) do
    gravatar_url("chatlive@trifle.app", 64)
  end

  defp avatar_alt(%{role: "assistant"}), do: "Trifle AI avatar"
  defp avatar_alt(_), do: "Your avatar"

  defp format_timestamp(nil), do: nil

  defp format_timestamp(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%H:%M")
  rescue
    _ -> ""
  end

  defp format_timestamp(_), do: ""

  defp gravatar_url(email, size) when is_binary(email) do
    trimmed = String.trim(email)

    if trimmed == "" do
      default_gravatar(size)
    else
      trimmed
      |> String.downcase()
      |> then(&:crypto.hash(:md5, &1))
      |> Base.encode16(case: :lower)
      |> then(fn hash -> "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=identicon" end)
    end
  end

  defp gravatar_url(_email, size), do: default_gravatar(size)

  defp default_gravatar(size), do: "https://www.gravatar.com/avatar/?s=#{size}&d=identicon"
end
