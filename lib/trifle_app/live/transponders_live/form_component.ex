defmodule TrifleApp.TranspondersLive.FormComponent do
  use TrifleApp, :live_component

  import TrifleApp.Components.PathInput, only: [path_autocomplete_input: 1]

  alias Trifle.Organizations
  alias Trifle.Organizations.{Database, Project}
  alias Trifle.Stats.Source
  alias TrifleApp.PathSuggestions

  @path_refresh_ttl_ms 60_000
  @expression_type "Trifle.Stats.Transponder.Expression"

  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Create or edit transponders to collect data from your applications.</:subtitle>
      </.header>

      <.form_container
        for={@form}
        id="transponder-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.form_field
          field={@form[:name]}
          type="text"
          label="Name"
          placeholder="e.g., Conversion Rate Calculator"
        />
        <.form_field
          field={@form[:key]}
          type="text"
          label="Key Pattern"
          placeholder="e.g., customer::(.*)::orders"
        />
        <%= if hint = path_status_message(@path_fetch_state) do %>
          <p class={"-mt-2 mb-4 text-xs #{path_hint_class(elem(hint, 1))}"}>
            {elem(hint, 0)}
          </p>
        <% end %>

        <input type="hidden" name="transponder[type]" value={expression_type()} />

        <div class="space-y-4">
          <div>
            <.label>Paths</.label>
            <div class="mt-2 space-y-2">
              <%= for {path, index} <- Enum.with_index(expression_paths(@config_values)) do %>
                <div class="flex items-center gap-2">
                  <div class="h-9 w-9 flex items-center justify-center rounded-md bg-slate-100 text-slate-700 dark:bg-slate-700 dark:text-slate-200 text-sm font-medium">
                    {letter_for_index(index)}
                  </div>
                  <div class="flex-1 min-w-0">
                    <.path_autocomplete_input
                      id={"transponder-expression-path-#{index}"}
                      name="transponder[config][paths][]"
                      value={path}
                      placeholder="metrics.duration.average"
                      path_options={@path_options}
                      input_class="block w-full rounded-md border-0 py-1.5 pl-3 pr-3 text-gray-900 dark:text-white bg-white dark:bg-slate-800 ring-1 ring-inset ring-gray-300 dark:ring-slate-600 placeholder:text-gray-400 dark:placeholder:text-slate-400 focus:ring-2 focus:ring-inset focus:ring-teal-600 dark:focus:ring-teal-500 sm:text-sm sm:leading-6"
                    />
                  </div>
                  <button
                    type="button"
                    phx-click="remove_expression_path"
                    phx-target={@myself}
                    phx-value-index={index}
                    class="inline-flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-md bg-slate-200 text-slate-700 hover:bg-slate-300 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-slate-700 dark:text-slate-200 dark:hover:bg-slate-600"
                    aria-label="Remove path"
                    disabled={length(expression_paths(@config_values)) == 1}
                  >
                    &minus;
                  </button>
                </div>
              <% end %>
            </div>
            <button
              type="button"
              phx-click="add_expression_path"
              phx-target={@myself}
              class="mt-2 inline-flex items-center gap-1 rounded-md bg-teal-500 px-3 py-2 text-sm font-medium text-white hover:bg-teal-600 dark:bg-teal-600 dark:hover:bg-teal-500"
            >
              <span aria-hidden="true">+</span>
              <span>Add path</span>
            </button>
            <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
              Paths are mapped to variables in order: a, b, c, …
            </p>
          </div>

          <div>
            <.label>Expression</.label>
            <input
              type="text"
              id="transponder-expression"
              name="transponder[config][expression]"
              value={@config_values["expression"] || @config_values[:expression] || ""}
              placeholder="(a + b) / c"
              phx-debounce="300"
              class="mt-2 block w-full rounded-md border-0 py-1.5 pl-3 pr-3 text-gray-900 dark:text-white bg-white dark:bg-slate-800 ring-1 ring-inset ring-gray-300 dark:ring-slate-600 placeholder:text-gray-400 dark:placeholder:text-slate-400 focus:ring-2 focus:ring-inset focus:ring-teal-600 dark:focus:ring-teal-500 sm:text-sm sm:leading-6"
            />
            <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
              Use variables a…{last_expression_letter(@config_values)} with +, -, *, /, parentheses, and functions like sum(a, b), max(a, b, c), mean(a, b), sqrt(a).
            </p>
            <%= if @expression_error do %>
              <p class="mt-1 text-xs text-rose-600 dark:text-rose-400">{@expression_error}</p>
            <% end %>
          </div>

          <div>
            <.label>Response Path</.label>
            <.path_autocomplete_input
              id="transponder-response-path"
              name="transponder[config][response_path]"
              value={@config_values["response_path"] || @config_values[:response_path] || ""}
              placeholder="metrics.duration.per_minute"
              path_options={@path_options}
              input_class="mt-2 block w-full rounded-md border-0 py-1.5 pl-3 pr-3 text-gray-900 dark:text-white bg-white dark:bg-slate-800 ring-1 ring-inset ring-gray-300 dark:ring-slate-600 placeholder:text-gray-400 dark:placeholder:text-slate-400 focus:ring-2 focus:ring-inset focus:ring-teal-600 dark:focus:ring-teal-500 sm:text-sm sm:leading-6"
            />
          </div>
        </div>

        <:actions>
          <.form_actions>
            <.secondary_button type="button" phx-click={JS.patch(@patch)}>
              Cancel
            </.secondary_button>
            <.primary_button phx-disable-with={
              if @action == :new, do: "Creating...", else: "Saving..."
            }>
              {if @action == :new, do: "Create Transponder", else: "Update Transponder"}
            </.primary_button>
          </.form_actions>
        </:actions>
      </.form_container>
    </div>
    """
  end

  def mount(socket) do
    {:ok, socket}
  end

  def update(%{transponder: transponder} = assigns, socket) do
    {:ok,
     socket
     |> assign_new(:path_options, fn -> [] end)
     |> assign_new(:path_fetch_state, fn -> :idle end)
     |> assign_new(:path_fetch_meta, fn -> %{} end)
     |> assign_new(:path_fetch_fingerprint, fn -> nil end)
     |> assign_new(:path_fetch_last_checked, fn -> nil end)
     |> assign(assigns)
     |> assign(:selected_type, @expression_type)
     |> assign(:expression_error, nil)
     |> assign(
       :config_values,
       normalize_config_values(@expression_type, transponder.config || %{})
     )
     |> assign_form(Organizations.change_transponder(transponder))
     |> maybe_refresh_path_options()}
  end

  def handle_event("validate", %{"transponder" => transponder_params}, socket) do
    transponder_params = Map.put(transponder_params, "type", @expression_type)
    config_values = Map.get(transponder_params, "config", %{})
    merged_config = Map.merge(socket.assigns.config_values, config_values)
    selected_type = @expression_type

    changeset =
      socket.assigns.transponder
      |> Organizations.change_transponder(transponder_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:selected_type, selected_type)
     |> assign(:config_values, normalize_config_values(selected_type, merged_config))
     |> assign(:expression_error, expression_error(selected_type, merged_config))
     |> assign_form(changeset)
     |> maybe_refresh_path_options()}
  end

  def handle_event("add_expression_path", _params, socket) do
    paths = expression_paths(socket.assigns.config_values)
    updated_paths = paths ++ [""]
    new_config = Map.put(socket.assigns.config_values, "paths", updated_paths)

    {:noreply,
     socket
     |> assign(:config_values, new_config)
     |> assign(:expression_error, expression_error(@expression_type, new_config))}
  end

  def handle_event("remove_expression_path", %{"index" => index}, socket) do
    idx = String.to_integer(index)

    updated_paths =
      socket.assigns.config_values
      |> expression_paths()
      |> Enum.with_index()
      |> Enum.reject(fn {_path, i} -> i == idx end)
      |> Enum.map(&elem(&1, 0))
      |> then(fn list -> if Enum.empty?(list), do: [""], else: list end)

    new_config = Map.put(socket.assigns.config_values, "paths", updated_paths)

    {:noreply,
     socket
     |> assign(:config_values, new_config)
     |> assign(:expression_error, expression_error(@expression_type, new_config))}
  end

  def handle_event("save", %{"transponder" => transponder_params}, socket) do
    transponder_params = Map.put(transponder_params, "type", @expression_type)
    # Get config from the form submission and merge with component state
    form_config = Map.get(transponder_params, "config", %{})
    merged_config = Map.merge(socket.assigns.config_values, form_config)

    merged_config =
      merged_config
      |> maybe_clean_expression_paths(@expression_type)

    # Filter out empty values from config
    clean_config = Enum.reject(merged_config, fn {_k, v} -> v == "" or is_nil(v) end) |> Map.new()

    transponder_params = Map.put(transponder_params, "config", clean_config)
    save_transponder(socket, socket.assigns.action, transponder_params)
  end

  defp save_transponder(socket, :edit, transponder_params) do
    case Organizations.update_transponder(socket.assigns.transponder, transponder_params) do
      {:ok, transponder} ->
        notify_parent({:updated, transponder})

        {:noreply,
         socket
         |> put_flash(:info, "Transponder updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign_form(changeset)
         |> maybe_refresh_path_options()}
    end
  end

  defp save_transponder(socket, :new, transponder_params) do
    source = socket.assigns.source
    next_order = Organizations.get_next_transponder_order(source)

    attrs =
      transponder_params
      |> Map.put("order", next_order)
      |> maybe_put_source_specific_attrs(source)

    case create_transponder_for_source(source, attrs) do
      {:ok, transponder} ->
        notify_parent({:saved, transponder})

        {:noreply,
         socket
         |> put_flash(:info, "Transponder created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign_form(changeset)
         |> maybe_refresh_path_options()}
    end
  end

  defp create_transponder_for_source(%Database{} = database, attrs) do
    Organizations.create_transponder_for_database(database, attrs)
  end

  defp create_transponder_for_source(%Project{} = project, attrs) do
    Organizations.create_transponder_for_project(project, attrs)
  end

  defp maybe_put_source_specific_attrs(attrs, %Database{} = database) do
    Map.put(attrs, "database_id", database.id)
  end

  defp maybe_put_source_specific_attrs(attrs, _), do: attrs

  defp maybe_refresh_path_options(socket, opts \\ []) do
    stats_source = stats_source(socket.assigns)
    key = current_transponder_key(socket)

    cond do
      is_nil(stats_source) ->
        socket
        |> assign(:path_options, [])
        |> assign(:path_fetch_state, :missing_source)
        |> assign(:path_fetch_fingerprint, nil)
        |> assign(:path_fetch_meta, %{})

      key in [nil, ""] ->
        socket
        |> assign(:path_options, [])
        |> assign(:path_fetch_state, :awaiting_key)
        |> assign(:path_fetch_fingerprint, nil)
        |> assign(:path_fetch_meta, %{})

      regex_key?(key) ->
        socket
        |> assign(:path_options, [])
        |> assign(:path_fetch_state, :regex_disabled)
        |> assign(:path_fetch_fingerprint, nil)
        |> assign(:path_fetch_meta, %{})

      true ->
        case should_fetch_paths?(socket, stats_source, key, opts) do
          {:ok, fingerprint} ->
            socket
            |> assign(:path_fetch_state, :loading)
            |> assign(:path_fetch_meta, %{})
            |> do_refresh_path_options(stats_source, key, fingerprint)

          :skip ->
            socket
        end
    end
  end

  defp stats_source(%{source_type: :database, source: %Database{} = database}),
    do: Source.from_database(database)

  defp stats_source(%{source_type: :project, source: %Project{} = project}),
    do: Source.from_project(project)

  defp stats_source(_), do: nil

  defp current_transponder_key(socket) do
    form = socket.assigns[:form]

    cond do
      form && form[:key] && Map.has_key?(form[:key], :value) ->
        form[:key].value || ""

      socket.assigns[:transponder] && socket.assigns.transponder.key ->
        socket.assigns.transponder.key

      true ->
        ""
    end
    |> to_string()
    |> String.trim()
  rescue
    _ -> ""
  end

  defp regex_key?(key) when key in [nil, ""], do: false

  defp regex_key?(key) do
    Regex.match?(~r/[\[\]\(\)\^\$\+\?\|\\]/, key)
  rescue
    _ -> false
  end

  defp should_fetch_paths?(socket, source, key, opts) do
    fingerprint = path_fetch_fingerprint(source, key)
    force? = Keyword.get(opts, :force, false)
    last_fingerprint = socket.assigns[:path_fetch_fingerprint]
    last_checked = socket.assigns[:path_fetch_last_checked]
    state = socket.assigns[:path_fetch_state]

    cond do
      force? -> {:ok, fingerprint}
      last_fingerprint != fingerprint -> {:ok, fingerprint}
      match?({:error, _}, state) -> {:ok, fingerprint}
      state == :empty -> {:ok, fingerprint}
      stale_path_fetch?(last_checked) -> {:ok, fingerprint}
      true -> :skip
    end
  end

  defp stale_path_fetch?(nil), do: true

  defp stale_path_fetch?(timestamp) do
    System.monotonic_time(:millisecond) - timestamp > @path_refresh_ttl_ms
  end

  defp path_fetch_fingerprint(source, key) do
    "#{Source.type(source)}:#{Source.id(source)}:#{key}"
  end

  defp do_refresh_path_options(socket, source, key, fingerprint) do
    case PathSuggestions.sample_options(source, key) do
      {:ok, %{options: options, meta: meta}} ->
        state = if Enum.empty?(options), do: :empty, else: {:ready, meta}

        socket
        |> assign(:path_options, options)
        |> assign(:path_fetch_state, state)
        |> assign(:path_fetch_meta, meta)
        |> assign(:path_fetch_fingerprint, fingerprint)
        |> assign(:path_fetch_last_checked, System.monotonic_time(:millisecond))

      {:error, reason} ->
        socket
        |> assign(:path_options, [])
        |> assign(:path_fetch_state, {:error, reason})
        |> assign(:path_fetch_meta, %{})
        |> assign(:path_fetch_fingerprint, fingerprint)
        |> assign(:path_fetch_last_checked, System.monotonic_time(:millisecond))
    end
  end

  defp path_status_message(:missing_source),
    do: {"Select a source to enable path suggestions.", :muted}

  defp path_status_message(:awaiting_key),
    do: {"Enter a key pattern to preview available paths.", :muted}

  defp path_status_message(:regex_disabled),
    do: {"Autocomplete is disabled while the key uses regular expressions.", :warning}

  defp path_status_message(:loading), do: {"Sampling recent data for this key…", :muted}
  defp path_status_message(:empty), do: {"No paths were found in the sampled window.", :warning}

  defp path_status_message({:ready, meta}) do
    granularity = meta[:granularity] || "selected granularity"
    {"Suggestions refreshed from the last #{granularity} segment.", :success}
  end

  defp path_status_message({:error, reason}),
    do: {"Unable to load path suggestions#{format_path_error(reason)}.", :danger}

  defp path_status_message(_), do: nil

  defp path_hint_class(:muted), do: "text-slate-500 dark:text-slate-400"
  defp path_hint_class(:success), do: "text-teal-600 dark:text-teal-400"
  defp path_hint_class(:warning), do: "text-amber-600 dark:text-amber-400"
  defp path_hint_class(:danger), do: "text-rose-600 dark:text-rose-400"
  defp path_hint_class(_), do: "text-slate-500 dark:text-slate-400"

  defp format_path_error({:invalid_granularity, granularity}),
    do: " (invalid granularity #{granularity})"

  defp format_path_error({:no_granularity, _}), do: " (no granularities configured)"
  defp format_path_error(:missing_source), do: " (source missing)"
  defp format_path_error(:missing_key), do: " (key missing)"

  defp format_path_error(reason) do
    detail =
      case reason do
        value when is_binary(value) -> value
        value -> inspect(value)
      end

    " (#{detail})"
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp expression_paths(config_values) do
    config_values
    |> then(fn config -> Map.get(config, "paths") || Map.get(config, :paths) || [] end)
    |> case do
      [] -> [""]
      paths when is_list(paths) -> paths
      _ -> [""]
    end
  end

  defp letter_for_index(index) do
    <<?a + index>>
  rescue
    _ -> "?"
  end

  defp last_expression_letter(config_values) do
    paths = expression_paths(config_values)
    capped_index = Enum.min([Enum.max([length(paths) - 1, 0]), 25])
    letter_for_index(capped_index)
  end

  defp normalize_config_values(@expression_type, config) do
    config
    |> Map.put("paths", expression_paths(config))
  end

  defp normalize_config_values(_type, config), do: config

  defp expression_error(@expression_type, config) do
    paths = Map.get(config, "paths") || Map.get(config, :paths)
    expression = Map.get(config, "expression") || Map.get(config, :expression) || ""
    trimmed_expression = String.trim(to_string(expression))

    cond do
      trimmed_expression == "" ->
        nil

      paths in [nil, [], [""]] ->
        nil

      true ->
        case Trifle.Stats.Transponder.ExpressionEngine.validate(paths || [], trimmed_expression) do
          :ok -> nil
          {:error, %{message: message}} -> message
          {:error, other} -> inspect(other)
        end
    end
  end

  defp expression_error(_type, _config), do: nil

  defp maybe_clean_expression_paths(config, @expression_type) do
    paths =
      config
      |> then(fn cfg -> Map.get(cfg, "paths") || Map.get(cfg, :paths) || [] end)
      |> Enum.map(fn
        nil -> nil
        value -> String.trim(to_string(value))
      end)
      |> Enum.reject(&(&1 in [nil, ""]))

    Map.put(config, "paths", paths)
  end

  defp maybe_clean_expression_paths(config, _type), do: config

  defp expression_type, do: @expression_type
end
