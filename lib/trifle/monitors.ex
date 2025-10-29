defmodule Trifle.Monitors do
  @moduledoc """
  Domain logic for configuring and managing monitor definitions and their executions.
  """
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias Ecto.Multi
  alias Trifle.Accounts.User
  alias Trifle.Integrations
  alias Trifle.Monitors.{Alert, Execution, Monitor}
  alias Trifle.Monitors.TestDelivery
  alias Trifle.Monitors.Monitor.DeliveryMedium
  alias Trifle.Organizations.OrganizationMembership
  alias Trifle.Organizations
  alias Trifle.Repo

  @default_execution_limit 25
  @delivery_media_types [:pdf, :png_light, :png_dark]

  ## Query helpers

  defp scoped_monitors_query(%OrganizationMembership{} = membership) do
    from(m in Monitor,
      where: m.organization_id == ^membership.organization_id,
      order_by: [asc: m.inserted_at]
    )
  end

  ## Monitors

  @doc """
  Lists monitors visible to the provided membership.
  """
  def list_monitors_for_membership(
        %User{} = _user,
        %OrganizationMembership{} = membership,
        opts \\ []
      ) do
    scoped_monitors_query(membership)
    |> preload(^monitor_preloads(opts))
    |> Repo.all()
  end

  @doc """
  Fetches a monitor by id, scoped to the organization tied to the membership.
  """
  def get_monitor_for_membership!(%OrganizationMembership{} = membership, id, opts \\ []) do
    scoped_monitors_query(membership)
    |> where([m], m.id == ^id)
    |> preload(^monitor_preloads(opts))
    |> Repo.one!()
  end

  @doc """
  Creates a new monitor for the given membership.
  """
  def create_monitor_for_membership(
        %User{} = user,
        %OrganizationMembership{} = membership,
        attrs \\ %{}
      ) do
    attrs =
      attrs
      |> normalize_monitor_attrs()
      |> Map.put("organization_id", membership.organization_id)
      |> Map.put("created_by_id", user.id)

    monitor = %Monitor{organization_id: membership.organization_id}

    with {:ok, attrs} <- ensure_source_reference(attrs, membership, monitor) do
      monitor
      |> Monitor.changeset(stringify_keys(attrs))
      |> Repo.insert()
    end
  end

  @doc """
  Updates a monitor, ensuring it belongs to the membership's organization.
  """
  def update_monitor_for_membership(
        %Monitor{} = monitor,
        %OrganizationMembership{} = membership,
        attrs
      ) do
    if monitor.organization_id != membership.organization_id do
      {:error, :unauthorized}
    else
      attrs = normalize_monitor_attrs(attrs)

      with {:ok, attrs} <- ensure_source_reference(attrs, membership, monitor) do
        monitor
        |> Monitor.changeset(stringify_keys(attrs))
        |> Repo.update()
      end
    end
  end

  @doc """
  Deletes the provided monitor.
  """
  def delete_monitor_for_membership(%Monitor{} = monitor, %OrganizationMembership{} = membership) do
    if monitor.organization_id != membership.organization_id do
      {:error, :unauthorized}
    else
      Multi.new()
      |> Multi.delete_all(:alerts, from(a in Alert, where: a.monitor_id == ^monitor.id))
      |> Multi.delete(:monitor, monitor)
      |> Repo.transaction()
      |> case do
        {:ok, %{monitor: monitor}} ->
          {:ok, monitor}

        {:error, :monitor, changeset, _} ->
          {:error, changeset}

        {:error, :alerts, reason, _} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Builds a monitor changeset for forms.
  """
  def change_monitor(%Monitor{} = monitor, attrs \\ %{}) do
    Monitor.changeset(monitor, normalize_monitor_attrs(attrs))
  end

  @doc """
  Triggers a one-off delivery for the given monitor using the configured delivery channels.
  """
  def test_deliver_monitor(%Monitor{} = monitor, opts \\ []) do
    TestDelivery.deliver_monitor(monitor, opts)
  end

  @doc """
  Triggers a one-off delivery for a specific alert belonging to the monitor.
  """
  def test_deliver_alert(%Monitor{} = monitor, %Alert{} = alert, opts \\ []) do
    TestDelivery.deliver_alert(monitor, alert, opts)
  end

  ## Alerts

  @doc """
  Lists alerts belonging to the given monitor.
  """
  def list_alerts(%Monitor{} = monitor) do
    monitor
    |> Ecto.assoc(:alerts)
    |> Repo.all()
  end

  @doc """
  Fetches an alert belonging to the given monitor.
  """
  def get_alert!(%Monitor{} = monitor, id) do
    monitor
    |> Ecto.assoc(:alerts)
    |> Repo.get!(id)
  end

  @doc """
  Builds an alert changeset for forms.
  """
  def change_alert(%Alert{} = alert, attrs \\ %{}) do
    Alert.changeset(alert, attrs)
  end

  @doc """
  Creates an alert under the provided monitor.
  """
  def create_alert(%Monitor{} = monitor, attrs \\ %{}) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("monitor_id", monitor.id)

    %Alert{monitor_id: monitor.id}
    |> Alert.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an existing alert.
  """
  def update_alert(%Alert{} = alert, attrs) do
    alert
    |> Alert.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an alert.
  """
  def delete_alert(%Alert{} = alert), do: Repo.delete(alert)

  ## Executions

  @doc """
  Lists recent executions for a given monitor.
  """
  def list_recent_executions(%Monitor{} = monitor, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_execution_limit)

    monitor
    |> Ecto.assoc(:executions)
    |> order_by(desc: :triggered_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Creates a new execution record for a monitor.
  """
  def create_execution(%Monitor{} = monitor, attrs \\ %{}) do
    attrs =
      attrs
      |> normalize_execution_attrs()
      |> Map.put(:monitor_id, monitor.id)
      |> Map.put_new(:triggered_at, DateTime.utc_now())

    %Execution{}
    |> Execution.changeset(attrs)
    |> Repo.insert()
  end

  def change_execution(%Execution{} = execution, attrs \\ %{}) do
    Execution.changeset(execution, normalize_execution_attrs(attrs))
  end

  ## Helpers

  def default_report_settings do
    %{
      frequency: :weekly,
      timeframe: "7d",
      granularity: "1d"
    }
  end

  def default_alert_settings do
    %{
      alert_timeframe: "1h",
      alert_granularity: "5m",
      alert_metric_key: "",
      alert_metric_path: ""
    }
  end

  def default_delivery_medium do
    %{medium: :pdf}
  end

  def default_delivery_media do
    [default_delivery_medium()]
  end

  def default_delivery_channel do
    %{
      channel: :email,
      label: "Primary channel",
      target: ""
    }
  end

  def delivery_media_options do
    [
      %{value: :pdf, label: "PDF", description: "Downloadable report with multiple widgets"},
      %{value: :png_light, label: "PNG (light)", description: "Image snapshot using light theme"},
      %{value: :png_dark, label: "PNG (dark)", description: "Image snapshot using dark theme"}
    ]
  end

  def delivery_media_option_map do
    delivery_media_options()
    |> Map.new(fn option -> {option.value, option} end)
  end

  def delivery_options_for_membership(%OrganizationMembership{} = membership) do
    (email_delivery_options(membership) ++ slack_delivery_options(membership))
    |> Enum.uniq_by(& &1.handle)
    |> Enum.sort_by(&normalise_sort_key(Map.get(&1, :label, &1.handle)))
  end

  def delivery_channels_from_handles(handles, membership, existing_channels \\ [])

  def delivery_channels_from_handles(
        handles,
        %OrganizationMembership{} = membership,
        existing_channels
      )
      when is_list(handles) do
    options = delivery_options_for_membership(membership)
    index = Map.new(options, &{&1.handle, &1})

    existing_index =
      existing_channels
      |> List.wrap()
      |> Enum.reduce({%{}, MapSet.new()}, fn channel, {acc, seen} ->
        case channel_to_handle(channel) do
          nil ->
            {acc, seen}

          handle ->
            if MapSet.member?(seen, handle) do
              {acc, seen}
            else
              {Map.put(acc, handle, channel), MapSet.put(seen, handle)}
            end
        end
      end)
      |> elem(0)

    Enum.reduce(handles, {[], []}, fn handle, {channels, invalid} ->
      case Map.get(index, handle) do
        nil ->
          {channels, [handle | invalid]}

        option ->
          channel_map = option_to_channel_params(option, Map.get(existing_index, handle))
          {[channel_map | channels], invalid}
      end
    end)
    |> then(fn {channels, invalid} -> {Enum.reverse(channels), Enum.reverse(invalid)} end)
  end

  def delivery_channels_from_handles(_handles, _membership, _existing), do: {[], []}

  def delivery_handles_from_channels(channels) when is_list(channels) do
    channels
    |> Enum.reduce([], fn channel, acc ->
      case channel_to_handle(channel) do
        nil -> acc
        handle -> [handle | acc]
      end
    end)
    |> Enum.reverse()
  end

  def delivery_handles_from_channels(_), do: []

  def delivery_media_from_types(types, existing_media \\ [])

  def delivery_media_from_types(types, existing_media) when is_list(types) do
    {valid, invalid} =
      types
      |> Enum.reduce({[], []}, fn value, {accepted, rejected} ->
        case normalize_delivery_media_type(value) do
          {:ok, medium} -> {[medium | accepted], rejected}
          :error -> {accepted, [format_invalid_medium(value) | rejected]}
        end
      end)

    normalized =
      valid
      |> Enum.reverse()
      |> Enum.uniq()

    existing_index =
      existing_media
      |> List.wrap()
      |> Enum.reduce(%{}, fn entry, acc ->
        case fetch_delivery_medium(entry) do
          {:ok, medium} -> Map.put_new(acc, medium, entry)
          :error -> acc
        end
      end)

    media =
      Enum.map(normalized, fn medium ->
        delivery_medium_params(medium, Map.get(existing_index, medium))
      end)

    {media, Enum.reverse(invalid)}
  end

  def delivery_media_from_types(_types, _existing_media), do: {[], []}

  def delivery_media_types_from_media(media) when is_list(media) do
    media
    |> Enum.reduce([], fn entry, acc ->
      case fetch_delivery_medium(entry) do
        {:ok, medium} -> [medium | acc]
        :error -> acc
      end
    end)
    |> Enum.reverse()
  end

  def delivery_media_types_from_media(_), do: []

  defp email_delivery_options(%OrganizationMembership{} = membership) do
    from(m in OrganizationMembership,
      where: m.organization_id == ^membership.organization_id,
      join: u in assoc(m, :user),
      preload: [user: u],
      order_by: [asc: u.email]
    )
    |> Repo.all()
    |> Enum.map(fn membership ->
      user = membership.user
      email = user && user.email

      %{
        handle: "email##{email}",
        label: email,
        description: "Organization #{role_label(membership.role)}",
        channel: :email,
        target: email,
        config: %{"user_id" => user && user.id},
        badge: "Email"
      }
    end)
  end

  defp slack_delivery_options(%OrganizationMembership{} = membership) do
    membership.organization_id
    |> Integrations.list_slack_installations_for_org(preload_channels: true)
    |> Enum.flat_map(fn installation ->
      Enum.flat_map(installation.channels || [], fn channel ->
        if channel.enabled do
          name = channel.name || channel.channel_id
          handle = "slack_#{installation.reference}##{name}"

          [
            %{
              handle: handle,
              label: "##{name}",
              description: installation.team_name,
              channel: :slack_webhook,
              target: channel.channel_id,
              config: %{
                "installation_id" => installation.id,
                "installation_reference" => installation.reference,
                "team_name" => installation.team_name,
                "channel_id" => channel.id,
                "channel_name" => name
              },
              badge: "Slack"
            }
          ]
        else
          []
        end
      end)
    end)
  end

  defp option_to_channel_params(option, existing \\ nil) do
    channel = Map.get(option, :channel) || Map.get(option, "channel")
    normalized_channel = normalize_channel(channel) || :custom

    %{
      "id" =>
        existing_id(existing) ||
          Map.get(option, :id) ||
          Map.get(option, "id") ||
          Ecto.UUID.generate(),
      "channel" => Atom.to_string(normalized_channel),
      "label" => Map.get(option, :label) || Map.get(option, "label"),
      "target" => Map.get(option, :target) || Map.get(option, "target"),
      "config" => stringify_map(Map.get(option, :config) || Map.get(option, "config") || %{})
    }
  end

  defp existing_id(%Monitor.DeliveryChannel{id: id}) when is_binary(id), do: id
  defp existing_id(%DeliveryMedium{id: id}) when is_binary(id), do: id
  defp existing_id(%{"id" => id}) when is_binary(id), do: id
  defp existing_id(%{id: id}) when is_binary(id), do: id
  defp existing_id(_), do: nil

  defp channel_to_handle(%Monitor.DeliveryChannel{} = channel) do
    do_channel_to_handle(channel.channel, channel.target, channel.config)
  end

  defp channel_to_handle(%{channel: channel, target: target, config: config}) do
    do_channel_to_handle(channel, target, config)
  end

  defp channel_to_handle(channel) when is_map(channel) do
    do_channel_to_handle(
      Map.get(channel, :channel) || Map.get(channel, "channel"),
      Map.get(channel, :target) || Map.get(channel, "target"),
      Map.get(channel, :config) || Map.get(channel, "config")
    )
  end

  defp channel_to_handle(_), do: nil

  defp do_channel_to_handle(channel, target, config) do
    case normalize_channel(channel) do
      :email ->
        if present?(target), do: "email##{target}", else: nil

      :slack_webhook ->
        config = config || %{}

        reference =
          Map.get(config, "installation_reference") || Map.get(config, :installation_reference)

        channel_name = Map.get(config, "channel_name") || Map.get(config, :channel_name) || target

        if present?(reference) && present?(channel_name) do
          "slack_#{reference}##{channel_name}"
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp normalize_monitor_attrs(attrs) when is_map(attrs) do
    attrs
    |> cast_enum(:type, [:report, :alert])
    |> cast_enum(:status, [:active, :paused])
    |> cast_enum(:trigger_status, [:idle, :warning, :recovering, :alerting])
    |> cast_enum(:source_type, [:database, :project])
    |> update_nested(:report_settings, &normalize_report_settings/1)
    |> update_nested(:alert_settings, &normalize_alert_settings/1)
    |> apply_alert_settings()
    |> normalize_alert_fields()
    |> update_nested_list(:delivery_media, &normalize_delivery_medium/1)
    |> ensure_delivery_media_default()
    |> update_nested_list(:delivery_channels, &normalize_delivery_channel/1)
  end

  defp normalize_monitor_attrs(attrs), do: attrs

  defp normalize_execution_attrs(attrs) when is_map(attrs) do
    attrs
    |> update_nested(:details, &ensure_map/1)
  end

  defp normalize_execution_attrs(attrs), do: attrs

  defp ensure_source_reference(attrs, membership, monitor) do
    case resolve_source_reference(attrs) do
      {:ok, {type, id}} ->
        coerce_source(attrs, membership, monitor, type, id)

      :none ->
        cond do
          dashboard_id = fetch_attr(attrs, :dashboard_id) ->
            coerce_source_from_dashboard(attrs, membership, monitor, dashboard_id)

          monitor_has_source?(monitor) ->
            {:ok, attrs}

          true ->
            {:error, source_error_changeset(monitor, attrs, "Source selection is required")}
        end

      {:error, message} ->
        {:error, source_error_changeset(monitor, attrs, message)}
    end
  end

  defp resolve_source_reference(attrs) do
    case fetch_attr(attrs, :source) do
      %{} = source_map ->
        normalize_source_tuple(fetch_attr(source_map, :type), fetch_attr(source_map, :id))

      _ ->
        type = fetch_attr(attrs, :source_type)
        id = fetch_attr(attrs, :source_id)

        cond do
          present?(type) and present?(id) ->
            normalize_source_tuple(type, id)

          present?(type) or present?(id) ->
            {:error, "Source selection is incomplete"}

          true ->
            :none
        end
    end
  end

  defp normalize_source_tuple(type, id) do
    type =
      case type do
        nil -> nil
        value -> value |> to_string() |> String.trim() |> String.downcase()
      end

    id =
      case id do
        nil -> nil
        value -> value |> to_string() |> String.trim()
      end

    cond do
      type in ["database", "project"] and present?(id) ->
        {:ok, {String.to_existing_atom(type), id}}

      type in ["database", "project"] ->
        {:error, "Source identifier is required"}

      true ->
        {:error, "Invalid source selection"}
    end
  rescue
    ArgumentError ->
      {:error, "Invalid source selection"}
  end

  defp coerce_source(attrs, membership, monitor, :database, id) do
    case ensure_database_access(membership, id) do
      :ok ->
        {:ok,
         attrs
         |> drop_source_param()
         |> put_attr(:source_type, :database)
         |> put_attr(:source_id, id)}

      {:error, message} ->
        {:error, source_error_changeset(monitor, attrs, message)}
    end
  end

  defp coerce_source(attrs, membership, monitor, :project, id) do
    case ensure_project_access(membership, id) do
      :ok ->
        {:ok,
         attrs
         |> drop_source_param()
         |> put_attr(:source_type, :project)
         |> put_attr(:source_id, id)}

      {:error, message} ->
        {:error, source_error_changeset(monitor, attrs, message)}
    end
  end

  defp coerce_source_from_dashboard(attrs, membership, monitor, dashboard_id) do
    case fetch_dashboard_source(membership, dashboard_id) do
      {:ok, {type, id}} ->
        coerce_source(attrs, membership, monitor, type, id)

      {:error, message} ->
        {:error, source_error_changeset(monitor, attrs, message, :dashboard_id)}
    end
  end

  defp ensure_database_access(%OrganizationMembership{} = membership, id) when is_binary(id) do
    try do
      _ = Organizations.get_database_for_org!(membership.organization_id, id)
      :ok
    rescue
      Ecto.NoResultsError ->
        {:error, "Database is not part of this organization"}
    end
  end

  defp ensure_project_access(%OrganizationMembership{} = membership, id) when is_binary(id) do
    try do
      project = Organizations.get_project!(id)

      if project.user_id == membership.user_id do
        :ok
      else
        {:error, "Project is not available to this user"}
      end
    rescue
      Ecto.NoResultsError ->
        {:error, "Project not found"}
    end
  end

  defp fetch_dashboard_source(%OrganizationMembership{} = membership, dashboard_id)
       when is_binary(dashboard_id) do
    try do
      dashboard = Organizations.get_dashboard_for_membership!(membership, dashboard_id)
      normalize_source_tuple(dashboard.source_type, dashboard.source_id)
    rescue
      Ecto.NoResultsError ->
        {:error, "Dashboard not found"}
    end
  end

  defp fetch_attr(attrs, key) when is_atom(key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp fetch_attr(attrs, key) when is_binary(key) do
    Map.get(attrs, key) || Map.get(attrs, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(attrs, key)
  end

  defp put_attr(attrs, key, value) when is_atom(key) do
    string_key = Atom.to_string(key)

    attrs
    |> Map.put(string_key, value)
    |> Map.delete(key)
  end

  defp drop_source_param(attrs) do
    attrs
    |> Map.delete(:source)
    |> Map.delete("source")
  end

  defp source_error_changeset(monitor, attrs, message, field \\ :source_id) do
    monitor
    |> Monitor.changeset(attrs)
    |> Changeset.add_error(field, message)
  end

  defp monitor_has_source?(%Monitor{source_type: source_type, source_id: source_id}) do
    not is_nil(source_type) and not is_nil(source_id)
  end

  defp monitor_has_source?(_), do: false

  defp stringify_keys(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, val}, acc ->
      string_key =
        cond do
          is_atom(key) -> Atom.to_string(key)
          is_binary(key) -> key
          true -> to_string(key)
        end

      Map.put(acc, string_key, stringify_keys(val))
    end)
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp monitor_preloads(opts) do
    base =
      case Keyword.get(opts, :preload, []) do
        true -> [:executions, :dashboard, :organization]
        list when is_list(list) -> list
        _ -> []
      end

    [:alerts | List.wrap(base)]
    |> Enum.uniq()
  end

  defp cast_enum(attrs, key, valid) do
    case Map.fetch(attrs, key) do
      {:ok, value} ->
        case normalize_enum_value(value, valid) do
          {:ok, normalized} -> Map.put(attrs, key, normalized)
          :error -> Map.delete(attrs, key)
        end

      :error ->
        attrs
    end
  end

  defp update_nested(attrs, key, fun) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> Map.put(attrs, key, fun.(value))
      :error -> attrs
    end
  end

  defp update_nested_list(attrs, key, fun) do
    case Map.fetch(attrs, key) do
      {:ok, value} when is_list(value) ->
        Map.put(attrs, key, Enum.map(value, fun))

      {:ok, value} when is_map(value) ->
        ordered =
          value
          |> Enum.sort_by(fn {k, _v} -> parse_index_key(k) end)
          |> Enum.map(fn {_k, v} -> v end)

        Map.put(attrs, key, Enum.map(ordered, fun))

      _ ->
        attrs
    end
  end

  defp normalize_report_settings(nil), do: default_report_settings()
  defp normalize_report_settings(settings) when is_map(settings), do: settings
  defp normalize_report_settings(_), do: default_report_settings()

  defp normalize_alert_settings(nil), do: default_alert_settings()
  defp normalize_alert_settings(settings) when is_map(settings), do: settings
  defp normalize_alert_settings(_), do: default_alert_settings()

  defp apply_alert_settings(attrs) do
    {settings, attrs} =
      cond do
        Map.has_key?(attrs, :alert_settings) ->
          Map.pop(attrs, :alert_settings)

        Map.has_key?(attrs, "alert_settings") ->
          Map.pop(attrs, "alert_settings")

        true ->
          {nil, attrs}
      end

    case settings do
      %{} = settings_map ->
        attrs
        |> put_unless_present(:alert_metric_key, fetch_string(settings_map, ["metric_key"]))
        |> put_unless_present(:alert_metric_path, fetch_string(settings_map, ["metric_path"]))
        |> put_unless_present(:alert_timeframe, fetch_string(settings_map, ["timeframe"]))
        |> put_unless_present(:alert_granularity, fetch_string(settings_map, ["granularity"]))

      _ ->
        attrs
    end
  end

  defp normalize_alert_fields(attrs) do
    attrs
    |> normalize_string_field(:alert_metric_key)
    |> normalize_string_field(:alert_metric_path)
    |> normalize_string_field(:alert_timeframe)
    |> normalize_string_field(:alert_granularity)
  end

  defp normalize_delivery_medium(media) when is_map(media) do
    media
    |> cast_enum(:medium, @delivery_media_types)
  end

  defp normalize_delivery_medium(_), do: default_delivery_medium()

  defp ensure_delivery_media_default(attrs) when is_map(attrs) do
    media = fetch_attr(attrs, :delivery_media)

    cond do
      is_list(media) and Enum.reject(media, &empty_media_entry?/1) != [] ->
        attrs

      is_list(media) ->
        put_attr(attrs, :delivery_media, default_delivery_media())

      is_map(media) ->
        attrs

      media in [nil, "", %{}] ->
        put_attr(attrs, :delivery_media, default_delivery_media())

      true ->
        attrs
    end
  end

  defp ensure_delivery_media_default(attrs), do: attrs

  defp normalize_delivery_channel(channel) when is_map(channel) do
    channel
    |> cast_enum(:channel, [:email, :slack_webhook, :webhook, :custom])
    |> ensure_map_key(:config, %{})
  end

  defp normalize_delivery_channel(_), do: default_delivery_channel()

  defp empty_media_entry?(nil), do: true

  defp empty_media_entry?(value) when is_map(value) do
    medium = Map.get(value, :medium) || Map.get(value, "medium")

    case normalize_delivery_media_type(medium) do
      {:ok, _} -> false
      :error -> true
    end
  end

  defp empty_media_entry?(_), do: false

  defp normalize_delivery_media_type(value) do
    case normalize_enum_value(value, @delivery_media_types) do
      {:ok, medium} -> {:ok, medium}
      :error -> :error
    end
  end

  defp format_invalid_medium(value) when is_binary(value), do: value
  defp format_invalid_medium(value) when is_atom(value), do: Atom.to_string(value)
  defp format_invalid_medium(value), do: inspect(value)

  defp fetch_delivery_medium(%DeliveryMedium{medium: medium}) when not is_nil(medium),
    do: {:ok, medium}

  defp fetch_delivery_medium(%{"medium" => medium}) do
    normalize_delivery_media_type(medium)
  end

  defp fetch_delivery_medium(%{medium: medium}) do
    normalize_delivery_media_type(medium)
  end

  defp fetch_delivery_medium(_), do: :error

  defp delivery_medium_params(medium, existing \\ nil) do
    base =
      existing
      |> existing_medium_map()
      |> stringify_map()

    base
    |> Map.put("id", existing_id(existing) || Ecto.UUID.generate())
    |> Map.put("medium", Atom.to_string(medium))
  end

  defp existing_medium_map(%DeliveryMedium{} = medium) do
    medium
    |> Map.from_struct()
    |> Map.delete(:__meta__)
  end

  defp existing_medium_map(%{} = map), do: map
  defp existing_medium_map(_), do: %{}

  defp normalize_enum_value(value, valid) when is_atom(value) do
    if value in valid do
      {:ok, value}
    else
      :error
    end
  end

  defp normalize_enum_value(value, valid) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()
      |> String.replace("-", "_")
      |> String.replace(" ", "_")

    case Enum.find(valid, fn candidate -> Atom.to_string(candidate) == normalized end) do
      nil -> :error
      atom -> {:ok, atom}
    end
  end

  defp normalize_enum_value(_value, _valid), do: :error

  defp put_unless_present(attrs, key, nil), do: attrs

  defp put_unless_present(attrs, key, value) do
    case Map.fetch(attrs, key) do
      {:ok, existing} when existing not in [nil, ""] -> attrs
      _ -> Map.put(attrs, key, value)
    end
  end

  defp fetch_string(map, keys) do
    Enum.find_value(keys, fn key ->
      cond do
        Map.has_key?(map, key) ->
          Map.get(map, key)

        is_binary(key) ->
          atom_key = safe_to_existing_atom(key)

          if atom_key && Map.has_key?(map, atom_key) do
            Map.get(map, atom_key)
          else
            nil
          end

        is_atom(key) ->
          string_key = Atom.to_string(key)

          if Map.has_key?(map, string_key) do
            Map.get(map, string_key)
          else
            nil
          end

        true ->
          nil
      end
    end)
    |> normalize_string()
  end

  defp normalize_string_field(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> Map.put(attrs, key, normalize_string(value))
      :error -> attrs
    end
  end

  defp normalize_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_string(value) when is_atom(value), do: value |> Atom.to_string() |> String.trim()
  defp normalize_string(_value), do: nil

  defp safe_to_existing_atom(value) when is_binary(value) do
    try do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> nil
    end
  end

  defp safe_to_existing_atom(_), do: nil

  defp normalize_channel(nil), do: nil
  defp normalize_channel(value) when is_atom(value), do: value

  defp normalize_channel(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> String.replace(" ", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> nil
  end

  defp role_label(nil), do: "Member"

  defp role_label(role) when is_binary(role) do
    role
    |> String.replace("_", " ")
    |> String.trim()
    |> case do
      "" -> "Member"
      other -> String.capitalize(other)
    end
  end

  defp normalise_sort_key(nil), do: ""
  defp normalise_sort_key(value) when is_binary(value), do: String.downcase(value)
  defp normalise_sort_key(value), do: value |> to_string() |> String.downcase()

  defp ensure_map(value) when is_map(value), do: value

  defp ensure_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp ensure_map(_), do: %{}

  defp ensure_map_key(map, key, default) when is_map(map) do
    Map.put_new(map, key, default)
  end

  defp ensure_map_key(_map, _key, default), do: default

  defp stringify_map(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), stringify_value(value))
    end)
  end

  defp stringify_map(_), do: %{}

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(value), do: value

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)

  defp parse_index_key(key) when is_integer(key), do: key

  defp parse_index_key(key) when is_binary(key) do
    case Integer.parse(key) do
      {value, _} -> value
      :error -> 0
    end
  end

  defp parse_index_key(_), do: 0
end
