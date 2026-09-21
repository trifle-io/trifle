defmodule TrifleApp.TracesLive do
  use TrifleApp, :live_view

  alias Trifle.Stats.Source
  alias Trifle.Traces.{Activity, Reader}
  alias TrifleApp.TracesLive.Query
  alias TrifleApp.Components.Traces, as: View
  alias TrifleApp.DesignSystem.PathColors

  @auto_load_parts 100

  @impl true
  def mount(_params, _session, %{assigns: %{current_membership: nil}} = socket),
    do: {:ok, redirect(socket, to: ~p"/organization/profile")}

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Traces",
       sources: Reader.sources(socket.assigns.current_membership),
       source: nil,
       query: nil,
       params: %{},
       query_error: nil,
       tokens: %{},
       activity_input: nil,
       activity: Activity.build(nil),
       activity_error: nil,
       activity_loading: false,
       expanded_widget: nil,
       traces: [],
       cursor: nil,
       list_error: nil,
       list_loading: false,
       record: nil,
       entries: [],
       part: 0,
       detail_error: nil,
       detail_loading: false,
       previews: %{},
       preview_loading: false,
       preview_error: nil,
       attachments: [],
       footer_section: nil,
       attachments_requested: false,
       attachments_loading: false,
       attachments_error: nil,
       attachments_next_part: nil,
       collapsed: false
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    params = Query.params(params)
    id = params["source_id"] || List.first(socket.assigns.sources) |> source_id()
    params = if id, do: Map.put(params, "source_id", id), else: params

    with {:ok, source} <- Reader.source(socket.assigns.current_membership, id),
         {:ok, query} <- Query.parse(params, source, socket.assigns.query) do
      params =
        params
        |> Map.put("timeframe", query.timeframe)
        |> Map.put("granularity", query.granularity)

      query = %{query | params: params}
      old = socket.assigns.query
      source_changed = is_nil(old) or old.params["source_id"] != id
      range_changed = source_changed or old.from != query.from or old.to != query.to
      activity_changed = range_changed or old.granularity != query.granularity
      list_changed = range_changed or old.filters != query.filters
      detail_changed = source_changed or old.reference != query.reference

      socket =
        assign(socket,
          source: source,
          query: query,
          params: params,
          query_error: nil,
          collapsed: query.detail_expanded
        )

      socket = if activity_changed, do: load_activity(socket), else: rebuild_activity(socket)
      socket = if list_changed, do: load_list(socket, false), else: socket
      socket = if detail_changed, do: load_detail(socket), else: socket
      {:noreply, socket}
    else
      {:error, error} ->
        # Invalidate all pending reads, including when an invalid source is supplied.
        {:noreply,
         assign(socket,
           params: params,
           query_error: error,
           tokens: %{},
           source: nil,
           query: nil,
           collapsed: false,
           expanded_widget: nil,
           activity_loading: false,
           list_loading: false,
           detail_loading: false
         )}
    end
  end

  @impl true
  def handle_event("apply_filters", params, socket) do
    params = Map.take(params, ~w(path state tags tag_mode duration_min))
    patch(socket, Map.merge(socket.assigns.params, params))
  end

  def handle_event("open_reference", %{"reference" => reference}, socket),
    do: patch(socket, Map.put(socket.assigns.params, "reference", String.trim(reference)))

  def handle_event("close_trace", _, socket),
    do: patch(socket, Map.drop(socket.assigns.params, ["reference", "detail"]))

  def handle_event("toggle_list", _, socket) do
    if socket.assigns.query && socket.assigns.query.reference do
      params =
        if socket.assigns.collapsed,
          do: Map.delete(socket.assigns.params, "detail"),
          else: Map.put(socket.assigns.params, "detail", "expanded")

      patch(socket, params)
    else
      {:noreply, socket}
    end
  end

  def handle_event("expand_widget", %{"id" => "trace-activity"}, socket) do
    {:noreply,
     assign(socket, expanded_widget: if(socket.assigns.source, do: "trace-activity", else: nil))}
  end

  def handle_event("expand_widget", _, socket), do: {:noreply, socket}

  def handle_event("close_expanded_widget", _, socket),
    do: {:noreply, assign(socket, expanded_widget: nil)}

  def handle_event("load_more", _, socket) do
    if socket.assigns.cursor && !socket.assigns.list_loading,
      do: {:noreply, load_list(socket, true)},
      else: {:noreply, socket}
  end

  def handle_event("load_part", _, socket) do
    if socket.assigns.record && !socket.assigns.detail_loading &&
         socket.assigns.part < socket.assigns.record.parts,
       do: {:noreply, load_part(socket, socket.assigns.part + 1)},
       else: {:noreply, socket}
  end

  def handle_event("retry_detail", _, socket), do: {:noreply, load_detail(socket)}

  def handle_event("toggle_footer_section", %{"section" => section}, socket)
      when section in ~w(tags attachments metadata) do
    active = if socket.assigns.footer_section == section, do: nil, else: section
    socket = assign(socket, :footer_section, active)

    if active == "attachments" && socket.assigns.record &&
         !socket.assigns.attachments_requested,
       do: {:noreply, load_attachments(socket)},
       else: {:noreply, socket}
  end

  def handle_event(event, _, socket) when event in ["more_attachments", "retry_attachments"] do
    if socket.assigns.record && !socket.assigns.attachments_loading &&
         (socket.assigns.attachments_next_part || socket.assigns.attachments_error),
       do: {:noreply, load_attachments(socket)},
       else: {:noreply, socket}
  end

  def handle_event("preview", %{"part" => part, "row" => row}, socket) do
    with {part, ""} <- Integer.parse(part),
         {row, ""} <- Integer.parse(row),
         record when not is_nil(record) <- socket.assigns.record do
      {membership, id, reader} = context(socket)

      {:noreply,
       socket
       |> assign(preview_loading: true, preview_error: nil)
       |> task(:preview, fn ->
         with {:ok, artifact} <- reader.artifact(membership, id, record.reference, part, row),
              do: {:ok, {{part, row}, Reader.preview(artifact)}}
       end)}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:filter_bar, {:filter_changed, %{source: %{id: id}}}}, socket) do
    patch(socket, %{"source_id" => id})
  end

  def handle_info({:filter_bar, {:filter_changed, changes}}, socket) do
    params = socket.assigns.params

    if changes[:reload] do
      # Re-evaluate relative ranges on explicit refresh only, not on row selection.
      socket = assign(socket, query: nil)
      {:noreply, socket} = handle_params(params, "", socket)
      {:noreply, socket}
    else
      params = if changes[:source], do: %{"source_id" => changes.source.id}, else: params

      params =
        if changes[:granularity],
          do: Map.put(params, "granularity", changes.granularity),
          else: params

      params =
        if changes[:smart_timeframe_input],
          do: Map.put(params, "timeframe", changes.smart_timeframe_input),
          else: params

      fixed = Map.get(changes, :use_fixed_display, socket.assigns.query.fixed)

      params =
        if fixed do
          params
          |> Map.put("from", date_input(changes[:from] || socket.assigns.query.from))
          |> Map.put("to", date_input(changes[:to] || socket.assigns.query.to))
        else
          Map.drop(params, ["from", "to"])
        end

      # A play action can refresh the same relative URL.
      socket = if changes[:from] || changes[:to], do: assign(socket, query: nil), else: socket
      patch(socket, params)
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_async({kind, token}, result, socket) do
    if socket.assigns.tokens[kind] == token do
      result =
        case result do
          {:ok, value} -> value
          _ -> {:error, :storage_unavailable}
        end

      {:noreply, finish(kind, result, socket)}
    else
      {:noreply, socket}
    end
  end

  defp finish(:activity, {:ok, input}, socket),
    do: socket |> assign(activity_input: input, activity_loading: false) |> rebuild_activity()

  defp finish(:activity, {:error, _}, socket),
    do:
      assign(socket,
        activity_loading: false,
        activity_error: "Activity is unavailable. Refresh to retry."
      )

  defp finish(:list, {:ok, {result, append}}, socket) do
    traces = if append, do: socket.assigns.traces ++ result.traces, else: result.traces

    assign(socket,
      traces: Enum.uniq_by(traces, & &1.reference),
      cursor: result.cursor,
      list_loading: false
    )
  end

  defp finish(:list, {:error, _}, socket),
    do:
      assign(socket,
        list_loading: false,
        list_error: "Traces could not be loaded. Refresh to retry."
      )

  defp finish(:detail, {:ok, record}, socket) do
    socket = assign(socket, record: record, detail_loading: false)
    if record.parts > 0, do: load_part(socket, 1), else: socket
  end

  defp finish(:detail, {:error, _}, socket),
    do:
      assign(socket,
        detail_loading: false,
        detail_error: "Trace not found or storage is unavailable."
      )

  defp finish(:part, {:ok, {entries, part}}, socket) do
    socket =
      assign(socket,
        entries: socket.assigns.entries ++ entries,
        part: part,
        detail_loading: false
      )

    # Append each part before requesting the next; beyond the initial limit,
    # the existing button continues loading one part at a time.
    if part < min(socket.assigns.record.parts, @auto_load_parts),
      do: load_part(socket, part + 1),
      else: socket
  end

  defp finish(:part, {:error, _}, socket),
    do:
      assign(socket,
        detail_loading: false,
        detail_error: "Stored content is missing, expired, or unavailable."
      )

  defp finish(:preview, {:ok, {key, preview}}, socket),
    do:
      assign(socket,
        previews: Map.put(socket.assigns.previews, key, preview),
        preview_loading: false
      )

  defp finish(:preview, {:error, _}, socket),
    do: assign(socket, preview_loading: false, preview_error: "Attachment is unavailable.")

  defp finish(:attachments, {:ok, result}, socket) do
    assign(socket,
      attachments:
        Enum.uniq_by(socket.assigns.attachments ++ result.attachments, &{&1.part, &1.row}),
      attachments_loading: false,
      attachments_next_part: result.next_part
    )
  end

  defp finish(:attachments, {:error, _}, socket),
    do:
      assign(socket,
        attachments_loading: false,
        attachments_error: "Attachments could not be loaded."
      )

  defp load_activity(socket) do
    {membership, id, _} = context(socket)
    q = socket.assigns.query
    activity = Application.get_env(:trifle, :trace_activity, Activity)

    socket
    |> assign(
      activity_input: nil,
      activity: Activity.build(nil),
      activity_error: nil,
      activity_loading: true
    )
    |> task(:activity, fn -> activity.fetch(membership, id, q.from, q.to, q.granularity) end)
  end

  defp rebuild_activity(socket),
    do:
      assign(socket,
        activity:
          Activity.build(
            socket.assigns.activity_input,
            socket.assigns.query.path,
            socket.assigns.query.filters[:state]
          )
      )

  defp load_list(socket, append) do
    {membership, id, reader} = context(socket)
    filters = socket.assigns.query.filters
    filters = if append, do: Keyword.put(filters, :cursor, socket.assigns.cursor), else: filters
    socket = if append, do: socket, else: assign(socket, traces: [], cursor: nil)

    socket
    |> assign(list_loading: true, list_error: nil)
    |> task(:list, fn ->
      with {:ok, result} <- reader.search(membership, id, filters), do: {:ok, {result, append}}
    end)
  end

  defp load_detail(socket) do
    {membership, id, reader} = context(socket)
    reference = socket.assigns.query.reference

    socket =
      assign(socket,
        record: nil,
        entries: [],
        part: 0,
        detail_error: nil,
        previews: %{},
        preview_loading: false,
        preview_error: nil,
        attachments: [],
        footer_section: nil,
        attachments_requested: false,
        attachments_loading: false,
        attachments_error: nil,
        attachments_next_part: nil,
        detail_loading: false,
        tokens: Map.drop(socket.assigns.tokens, [:detail, :part, :preview, :attachments])
      )

    if reference do
      socket
      |> assign(detail_loading: true)
      |> task(:detail, fn -> reader.detail(membership, id, reference) end)
    else
      socket
    end
  end

  defp load_part(socket, part) do
    {membership, id, reader} = context(socket)
    reference = socket.assigns.record.reference

    socket
    |> assign(detail_loading: true, detail_error: nil)
    |> task(:part, fn ->
      with {:ok, entries} <- reader.part(membership, id, reference, part),
           do: {:ok, {entries, part}}
    end)
  end

  defp load_attachments(socket) do
    {membership, id, reader} = context(socket)
    reference = socket.assigns.record.reference
    after_part = socket.assigns.attachments_next_part || 0

    socket
    |> assign(attachments_requested: true, attachments_loading: true, attachments_error: nil)
    |> task(:attachments, fn -> reader.attachments(membership, id, reference, after_part) end)
  end

  defp task(socket, kind, fun) do
    token = make_ref()

    socket =
      case socket.assigns.tokens[kind] do
        nil -> socket
        previous -> cancel_async(socket, {kind, previous})
      end

    socket
    |> assign(tokens: Map.put(socket.assigns.tokens, kind, token))
    |> start_async({kind, token}, fun)
  end

  defp context(socket),
    do:
      {socket.assigns.current_membership, Source.id(socket.assigns.source),
       Application.get_env(:trifle, :trace_reader, Reader)}

  defp patch(socket, params), do: {:noreply, push_patch(socket, to: Query.url(params))}
  defp source_id(nil), do: nil
  defp source_id(source), do: Source.id(source)
  defp date_input(date), do: date |> DateTime.to_naive() |> NaiveDateTime.to_iso8601()

  @impl true
  def render(assigns) do
    # Include unfiltered activity paths, paginated rows and direct-link details.
    # Every surface receives the same sibling colors, even when only one row is visible.
    paths = assigns.activity.paths ++ Enum.map(assigns.traces, & &1.key)
    paths = if assigns.record, do: [assigns.record.key | paths], else: paths
    assigns = assign(assigns, :path_colors, PathColors.build(paths, "/"))

    ~H"""
    <div
      id="traces-root"
      class={[@source && "traces-workspace", "text-slate-900 dark:text-slate-100"]}
    >
      <%= if @source do %>
        <h1 class="sr-only">Traces</h1>
        <.live_component
          module={TrifleApp.Components.FilterBar}
          id="traces-filter-bar"
          config={@query.config}
          granularity={@query.granularity}
          available_granularities={@query.granularities}
          from={@query.from}
          to={@query.to}
          smart_timeframe_input={@query.timeframe}
          use_fixed_display={@query.fixed}
          show_timeframe_dropdown={false}
          show_granularity_dropdown={false}
          show_controls={true}
          sources={@sources}
          selected_source={Source.reference(@source)}
          force_granularity_dropdown={false}
          loading={@list_loading or @activity_loading}
        >
          <:attachment>
            <View.filters params={@params} paths={@activity.paths} />
          </:attachment>
        </.live_component>
        <div class="traces-scrollport">
          <div class="traces-content">
            <View.activity
              activity={@activity}
              path={@query.path}
              state={@query.filters[:state]}
              loading={@activity_loading}
              error={@activity_error}
              timezone={@query.config.time_zone}
              presentation="widget"
            />
            <div
              id="trace-panels"
              class="trace-panels flex rounded-lg border border-slate-200 bg-white dark:border-slate-700 dark:bg-slate-900"
            >
              <View.list
                traces={@traces}
                path_colors={@path_colors}
                params={@params}
                selected={@query.reference}
                collapsed={@collapsed}
                loading={@list_loading}
                error={@list_error}
                cursor={@cursor}
              />
              <View.detail
                params={@params}
                record={@record}
                path_colors={@path_colors}
                entries={@entries}
                selected={@query.reference}
                collapsed={@collapsed}
                loading={@detail_loading}
                error={@detail_error}
                part={@part}
                source_id={Source.id(@source)}
                previews={@previews}
                preview_loading={@preview_loading}
                preview_error={@preview_error}
                attachments={@attachments}
                footer_section={@footer_section}
                attachments_requested={@attachments_requested}
                attachments_loading={@attachments_loading}
                attachments_error={@attachments_error}
                attachments_next_part={@attachments_next_part}
              />
            </div>
          </div>
        </div>
        <%!-- Keep the fixed modal outside size containment and the scrollport. --%>
        <View.activity
          :if={@expanded_widget == "trace-activity"}
          activity={@activity}
          path={@query.path}
          state={@query.filters[:state]}
          loading={@activity_loading}
          error={@activity_error}
          timezone={@query.config.time_zone}
          expanded={true}
          presentation="expanded"
        />
      <% else %>
        <div class="mx-auto max-w-xl py-16">
          <h1 class="text-xl font-semibold">Traces</h1>
          <p class="mt-3 text-slate-600 dark:text-slate-300">
            {if is_binary(@query_error),
              do: @query_error,
              else:
                "Choose an active database with Traces configured to browse its activity and stored traces."}
          </p>
          <.link :if={@sources != []} patch={~p"/traces"} class="mt-4 inline-block text-teal-600">
            Reset filters
          </.link>
          <.link navigate={~p"/dbs"} class="ml-4 mt-4 inline-block text-teal-600">
            Go to Databases
          </.link>
        </div>
      <% end %>
    </div>
    """
  end
end
