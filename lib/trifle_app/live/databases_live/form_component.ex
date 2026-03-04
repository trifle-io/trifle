defmodule TrifleApp.DatabasesLive.FormComponent do
  use TrifleApp, :live_component

  import TrifleApp.Components.GranularitySelect, only: [granularity_select: 1]
  import TrifleApp.Components.TimeframeInput, only: [timeframe_input: 1]

  alias Ecto.Changeset
  alias Trifle.Organizations
  alias Trifle.Organizations.Database
  alias Trifle.SqliteUploads
  alias TrifleApp.Granularity

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form_container for={@form} phx-target={@myself} phx-change="validate" phx-submit="save">
        <:header title={@title} subtitle="Configure database connection for Trifle::Stats drivers" />

        <.form_field field={@form[:display_name]} label="Display Name" required />

        <.form_field
          field={@form[:driver]}
          type="select"
          label="Driver"
          options={Database.drivers() |> Enum.map(&{driver_display_name(&1), &1})}
          prompt="Choose a driver..."
          disabled={@action == :edit}
        />

        <%= if @selected_driver && Database.requires_host?(@selected_driver) do %>
          <.form_field field={@form[:host]} label="Host" />
        <% end %>

        <%= if @selected_driver && Database.requires_port?(@selected_driver) do %>
          <.form_field
            field={@form[:port]}
            type="number"
            label="Port"
            placeholder={
              if @selected_driver, do: to_string(Database.default_port(@selected_driver)), else: ""
            }
          />
        <% end %>

        <%= if @selected_driver && @selected_driver != "redis" && @selected_driver != "sqlite" do %>
          <.form_field field={@form[:database_name]} label="Database Name" />
        <% end %>

        <%= if @selected_driver && @selected_driver == "sqlite" do %>
          <div class="space-y-2 mb-4">
            <label class="block text-sm font-medium text-gray-900 dark:text-white">
              SQLite File Upload
            </label>
            <.live_file_input
              upload={@uploads.sqlite_file}
              phx-target={@myself}
              class="block w-full text-sm text-gray-900 dark:text-white file:mr-4 file:rounded-md file:border-0 file:bg-teal-50 file:px-3 file:py-2 file:text-sm file:font-semibold file:text-teal-700 hover:file:bg-teal-100 dark:file:bg-teal-500/20 dark:file:text-teal-200"
            />
            <p class="text-xs text-gray-600 dark:text-gray-400">
              {sqlite_upload_help_text()}
            </p>

            <%= for entry <- @uploads.sqlite_file.entries do %>
              <div class="text-xs text-gray-600 dark:text-gray-400">
                {entry.client_name} ({entry.progress}%)
              </div>
              <%= for error <- upload_errors(@uploads.sqlite_file, entry) do %>
                <p class="text-sm text-red-600 dark:text-red-400">
                  {upload_error_message(error)}
                </p>
              <% end %>
            <% end %>

            <%= for error <- upload_errors(@uploads.sqlite_file) do %>
              <p class="text-sm text-red-600 dark:text-red-400">{upload_error_message(error)}</p>
            <% end %>
          </div>

          <.form_field
            field={@form[:file_path]}
            label="Database File Path"
            placeholder="e.g., /path/to/database.sqlite"
            help_text="Optional fallback for manual server-side paths. Uploaded file is used when provided."
          />
        <% end %>

        <%= if @selected_driver && Database.shows_username?(@selected_driver) do %>
          <.form_field field={@form[:username]} label="Username" />
        <% end %>

        <%= if @selected_driver && Database.shows_password?(@selected_driver) do %>
          <.form_field field={@form[:password]} type="password" label="Password" />
        <% end %>

        <%= if @selected_driver == "mongo" do %>
          <.form_field
            field={@form[:auth_database]}
            label="Authentication Database"
            help_text="Database to authenticate against (usually 'admin'). Leave empty to authenticate against the target database."
            placeholder="admin"
          />
        <% end %>

        <%= if @selected_driver do %>
          <div class="border-t pt-6 mt-6">
            <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-4">
              Time Configuration
            </h3>

            <div class="space-y-2">
              <label
                for={@form[:granularities].id}
                class="block text-sm font-medium text-gray-900 dark:text-white"
              >
                Granularities
              </label>
              <input
                id={@form[:granularities].id}
                name={@form[:granularities].name}
                type="text"
                value={granularities_to_string(@form[:granularities].value)}
                placeholder="1m, 1h, 1d, 1w, 1mo, 1q, 1y"
                class="block w-full rounded-lg border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-700 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
              />
              <p class="text-xs text-gray-600 dark:text-gray-400">
                Default: 1m, 1h, 1d, 1w, 1mo, 1q, 1y
              </p>
              <%= for error <- @form[:granularities].errors do %>
                <p class="text-sm text-red-600 dark:text-red-400">{translate_error(error)}</p>
              <% end %>
            </div>

            <.form_field
              field={@form[:time_zone]}
              type="select"
              label="Time Zone"
              options={@time_zones}
            />

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-4">
              <.timeframe_input
                field={@form[:default_timeframe]}
                label="Default Timeframe"
                placeholder="e.g. 24h, 7d, 1mo"
                help="Smart input used when Explore/Dashboards open without explicit timeframe."
              />
              <div>
                <.granularity_select
                  field={@form[:default_granularity]}
                  label="Default Granularity"
                  wrapper_class="grid grid-cols-1 sm:max-w-xs mt-2"
                  options={@granularity_options}
                  prompt="Select a granularity"
                />
                <p class="text-xs text-gray-600 dark:text-gray-400 mt-1">
                  Used as initial granularity in Explore/Dashboards.
                </p>
              </div>
            </div>
          </div>
        <% end %>

        <%= if @selected_driver && map_size(@config_options) > 0 do %>
          <div class="border-t pt-6 mt-6">
            <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-4">
              Configuration Options
            </h3>
            <p class="text-xs text-gray-600 dark:text-gray-400 mb-4">
              Driver-specific configuration settings.
            </p>

            <%= for {key, value} <- sort_config_options(@config_options) do %>
              <%= case config_field_type(key, @selected_driver) do %>
                <% :boolean -> %>
                  <div class="mb-4">
                    <input name={"database[config][#{key}]"} type="hidden" value="false" />
                    <label class="flex items-center space-x-3">
                      <input
                        name={"database[config][#{key}]"}
                        type="checkbox"
                        checked={is_config_value_true(@form, key, value)}
                        value="true"
                        class="rounded border-gray-300 text-teal-600 focus:ring-teal-500 dark:border-gray-600 dark:bg-gray-700"
                      />
                      <span class="text-sm font-medium text-gray-900 dark:text-white">
                        {humanize_config_key(key)}
                      </span>
                    </label>
                  </div>
                <% :joined_identifiers -> %>
                  <div class="mb-4">
                    <label class="block text-sm font-medium text-gray-900 dark:text-white mb-2">
                      {humanize_config_key(key)}
                    </label>
                    <% selected = joined_identifiers_value(@form, key, value) %>
                    <select
                      name={"database[config][#{key}]"}
                      class="block w-full rounded-md border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
                    >
                      <%= for {label, option_value} <- joined_identifiers_options() do %>
                        <option value={option_value} selected={selected == option_value}>
                          {label}
                        </option>
                      <% end %>
                    </select>
                  </div>
                <% :integer -> %>
                  <div class="mb-4">
                    <label class="block text-sm font-medium text-gray-900 dark:text-white mb-2">
                      {humanize_config_key(key)}{if is_nullable_field?(key), do: " (Optional)"}
                    </label>
                    <input
                      name={"database[config][#{key}]"}
                      type="number"
                      value={format_integer_value(get_config_value(@form, key, value))}
                      placeholder={
                        if is_nullable_field?(key), do: "Leave empty for no expiration", else: nil
                      }
                      class="block w-full rounded-md border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
                    />
                  </div>
                <% :string -> %>
                  <div class="mb-4">
                    <label class="block text-sm font-medium text-gray-900 dark:text-white mb-2">
                      {humanize_config_key(key)}
                    </label>
                    <input
                      name={"database[config][#{key}]"}
                      type="text"
                      value={get_config_value(@form, key, value)}
                      class="block w-full rounded-md border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
                    />
                  </div>
              <% end %>
            <% end %>
          </div>
        <% end %>

        <:actions>
          <.form_actions>
            <.secondary_button type="button" phx-click={JS.patch(@patch)}>
              Cancel
            </.secondary_button>
            <.primary_button phx-disable-with="Saving...">Save Database</.primary_button>
          </.form_actions>
        </:actions>
      </.form_container>
    </div>
    """
  end

  @impl true
  def update(%{database: database} = assigns, socket) do
    changeset = Organizations.change_database(database)
    selected_driver = database.driver

    config_options =
      if selected_driver, do: Database.default_config_options(selected_driver), else: %{}

    {:ok,
     socket
     |> ensure_sqlite_upload()
     |> assign(assigns)
     |> assign(:selected_driver, selected_driver)
     |> assign(:config_options, config_options)
     |> assign(:time_zones, time_zones())
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"database" => database_params}, socket) do
    selected_driver = selected_driver(socket, database_params)

    config_options =
      if selected_driver, do: Database.default_config_options(selected_driver), else: %{}

    changeset =
      socket.assigns.database
      |> Organizations.change_database(database_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> maybe_cancel_sqlite_upload(selected_driver)
     |> assign(:selected_driver, selected_driver)
     |> assign(:config_options, config_options)
     |> assign_form(changeset)}
  end

  def handle_event("save", %{"database" => database_params}, socket) do
    case maybe_attach_sqlite_upload(socket, database_params) do
      {:ok, database_params, uploaded_upload} ->
        save_database(socket, socket.assigns.action, database_params, uploaded_upload)

      {:error, reason} ->
        changeset =
          socket.assigns.database
          |> Organizations.change_database(database_params)
          |> Ecto.Changeset.add_error(:file_path, format_upload_error(reason))
          |> Map.put(:action, :validate)

        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp format_upload_error(reason) when is_binary(reason), do: reason

  defp format_upload_error({:http_error, status, body}) do
    "Object storage request failed (#{status}): #{preview_body(body)}"
  end

  defp format_upload_error({:request_failed, reason}) do
    "Object storage request failed: #{inspect(reason)}"
  end

  defp format_upload_error(reason), do: "SQLite upload failed: #{inspect(reason)}"

  defp preview_body(body) when is_binary(body), do: String.slice(body, 0, 300)
  defp preview_body(body), do: inspect(body, limit: 50, printable_limit: 300)

  defp save_database(socket, :edit, database_params, uploaded_upload) do
    case Organizations.update_database(socket.assigns.database, database_params) do
      {:ok, database} ->
        notify_parent({:saved, database})

        {:noreply,
         socket
         |> put_flash(:info, "Database updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        cleanup_uploaded_sqlite_upload(uploaded_upload)
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_database(socket, :new, database_params, uploaded_upload) do
    with org_id when is_binary(org_id) <- socket.assigns.database.organization_id do
      params = Map.put(database_params, "organization_id", org_id)

      case Organizations.create_database(params) do
        {:ok, database} ->
          notify_parent({:saved, database})

          {:noreply,
           socket
           |> put_flash(:info, "Database created successfully")
           |> push_patch(to: socket.assigns.patch)}

        {:error, %Ecto.Changeset{} = changeset} ->
          cleanup_uploaded_sqlite_upload(uploaded_upload)
          {:noreply, assign_form(socket, changeset)}
      end
    else
      _ ->
        cleanup_uploaded_sqlite_upload(uploaded_upload)

        {:noreply,
         socket
         |> put_flash(:error, "Unable to determine organization for this database.")}
    end
  end

  defp assign_form(socket, %Changeset{} = changeset) do
    granularities =
      changeset
      |> Changeset.get_field(:granularities)
      |> List.wrap()
      |> Enum.reject(&(&1 in [nil, ""]))

    default_granularity = Changeset.get_field(changeset, :default_granularity)

    options =
      granularities
      |> case do
        [] -> Database.default_granularities()
        list -> list
      end
      |> Granularity.options()
      |> ensure_current_option(default_granularity)

    socket
    |> assign(:form, to_form(changeset))
    |> assign(:granularity_options, options)
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp config_field_type("ssl", "postgres"), do: :boolean
  defp config_field_type("joined_identifiers", _), do: :joined_identifiers
  defp config_field_type("pool_size", _), do: :integer
  defp config_field_type("pool_timeout", _), do: :integer
  defp config_field_type("timeout", _), do: :integer
  defp config_field_type("expire_after", _), do: :integer
  defp config_field_type(_, _), do: :string

  defp humanize_config_key(key) do
    key
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp get_config_value(form, key, default_value) do
    case form.params do
      %{"config" => config} when is_map(config) ->
        Map.get(config, key, default_value)

      _ ->
        case form.data.config do
          nil -> default_value
          config when is_map(config) -> Map.get(config, key, default_value)
          _ -> default_value
        end
    end
  end

  defp joined_identifiers_options do
    [
      {"Separated (null)", "null"},
      {"Partial (partial)", "partial"},
      {"Joined (full)", "full"}
    ]
  end

  defp joined_identifiers_value(form, key, default_value) do
    value = get_config_value(form, key, default_value)

    case value do
      nil -> "null"
      "" -> "null"
      "null" -> "null"
      false -> "null"
      "false" -> "null"
      true -> "full"
      "true" -> "full"
      :full -> "full"
      "full" -> "full"
      :partial -> "partial"
      "partial" -> "partial"
      _ -> "full"
    end
  end

  defp is_config_value_true(form, key, default_value) do
    value = get_config_value(form, key, default_value)

    case value do
      true -> true
      "true" -> true
      _ -> false
    end
  end

  defp is_nullable_field?("expire_after"), do: true
  defp is_nullable_field?(_), do: false

  defp format_integer_value(nil), do: ""
  defp format_integer_value(value) when is_integer(value), do: to_string(value)
  defp format_integer_value(value) when is_binary(value), do: value
  defp format_integer_value(_), do: ""

  defp granularities_to_string(nil), do: ""
  defp granularities_to_string([]), do: ""

  defp granularities_to_string(granularities) when is_list(granularities) do
    Enum.join(granularities, ", ")
  end

  defp granularities_to_string(value) when is_binary(value), do: value
  defp granularities_to_string(_), do: ""

  defp sort_config_options(config_options) when is_map(config_options) do
    config_options
    |> Enum.sort_by(fn {key, _value} ->
      case key do
        "table_name" -> 0
        "collection_name" -> 1
        _ -> 2
      end
    end)
  end

  defp time_zones do
    now = DateTime.utc_now()

    Tzdata.zone_list()
    |> Enum.map(fn zone ->
      tzinfo = Timex.Timezone.get(zone, now)
      offset = Timex.TimezoneInfo.format_offset(tzinfo)
      label = "#{tzinfo.full_name} - #{tzinfo.abbreviation} (#{offset})"

      {label, tzinfo.full_name}
    end)
    |> Enum.uniq()
  end

  defp ensure_current_option(options, value) do
    cond do
      is_nil(value) or value == "" ->
        options

      Enum.any?(options, &(to_string(&1.value) == to_string(value))) ->
        options

      true ->
        options ++ Granularity.options([value])
    end
  end

  defp maybe_attach_sqlite_upload(socket, database_params) do
    case selected_driver(socket, database_params) do
      "sqlite" ->
        case consume_sqlite_upload(socket) do
          {:ok, nil} ->
            {:ok, database_params, nil}

          {:ok, %{file_path: uploaded_path, config_patch: config_patch} = uploaded_upload} ->
            updated_database_params =
              database_params
              |> Map.put("file_path", uploaded_path)
              |> SqliteUploads.apply_config_patch(config_patch)

            {:ok, updated_database_params, uploaded_upload}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:ok, database_params, nil}
    end
  end

  defp consume_sqlite_upload(socket) do
    {completed_entries, in_progress_entries} = uploaded_entries(socket, :sqlite_file)

    cond do
      in_progress_entries != [] ->
        {:error, "SQLite upload is still in progress. Wait for completion and try again."}

      completed_entries == [] ->
        {:ok, nil}

      true ->
        organization_id = socket.assigns.database.organization_id

        try do
          uploaded_uploads =
            consume_uploaded_entries(socket, :sqlite_file, fn %{path: path}, entry ->
              case SqliteUploads.store_upload_for_database(
                     %{path: path, filename: entry.client_name},
                     organization_id
                   ) do
                {:ok, uploaded_upload} ->
                  {:ok, uploaded_upload}

                {:error, reason} ->
                  throw({:sqlite_upload_failed, reason})
              end
            end)

          {:ok, List.last(uploaded_uploads)}
        catch
          {:sqlite_upload_failed, reason} ->
            {:error, reason}
        end
    end
  end

  defp cleanup_uploaded_sqlite_upload(nil), do: :ok

  defp cleanup_uploaded_sqlite_upload(%{file_path: path, config_patch: config_patch}) do
    SqliteUploads.delete_managed_upload(path, config_patch || %{})
  end

  defp cleanup_uploaded_sqlite_upload(_), do: :ok

  defp selected_driver(socket, database_params) do
    case database_params["driver"] do
      nil -> socket.assigns.database.driver
      "" -> nil
      driver -> driver
    end
  end

  defp maybe_cancel_sqlite_upload(socket, "sqlite"), do: socket

  defp maybe_cancel_sqlite_upload(socket, _selected_driver) do
    case socket.assigns do
      %{uploads: %{sqlite_file: upload}} ->
        Enum.reduce(upload.entries, socket, fn entry, acc ->
          cancel_upload(acc, :sqlite_file, entry.ref)
        end)

      _ ->
        socket
    end
  end

  defp sqlite_upload_help_text do
    max_mb = Trifle.Config.sqlite_upload_max_bytes() / 1_048_576
    "Accepted: .sqlite, .sqlite3, .db. Max size: #{Float.round(max_mb, 1)} MB."
  end

  defp upload_error_message(:too_large), do: "SQLite upload exceeded size limit."
  defp upload_error_message(:too_many_files), do: "Only one SQLite file can be uploaded."
  defp upload_error_message(:not_accepted), do: "Unsupported file type."
  defp upload_error_message(_), do: "Upload failed."

  defp ensure_sqlite_upload(socket) do
    case socket.assigns do
      %{uploads: %{sqlite_file: _upload}} ->
        socket

      _ ->
        allow_upload(socket, :sqlite_file,
          accept: :any,
          max_entries: 1,
          max_file_size: Trifle.Config.sqlite_upload_max_bytes(),
          auto_upload: true
        )
    end
  end
end
