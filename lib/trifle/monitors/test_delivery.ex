defmodule Trifle.Monitors.TestDelivery do
  @moduledoc false

  alias Trifle.Integrations
  alias Trifle.Integrations.Slack.Client, as: SlackClient
  alias Trifle.Monitors
  alias Trifle.Monitors.{Alert, Monitor}
  alias TrifleApp.Exports.MonitorLayout
  alias TrifleApp.Exporters.ChromeExporter
  alias TrifleApp.Exports.Layout
  alias Trifle.Mailer
  alias Swoosh.Attachment
  alias Swoosh.Email

  @default_media [:pdf]
  @default_monitor_viewport %{width: 1920, height: 1080}

  @spec deliver_monitor(Monitor.t(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def deliver_monitor(%Monitor{} = monitor, opts \\ []) do
    channels = monitor.delivery_channels || []
    media = resolve_media_types(monitor, opts)
    export_params = normalize_export_params(opts[:export_params])

    cond do
      Enum.empty?(channels) ->
        {:error, "No delivery targets configured for this monitor."}

      true ->
        with {:ok, exports} <-
               build_exports({:monitor, monitor}, media, export_params, opts),
             results <-
               deliver_to_channels(
                 monitor,
                 nil,
                 channels,
                 exports,
                 export_params,
                 opts
               ) do
          finalize_results(results, media)
        end
    end
  end

  @spec deliver_alert(Monitor.t(), Alert.t(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def deliver_alert(%Monitor{} = monitor, %Alert{} = alert, opts \\ []) do
    channels = monitor.delivery_channels || []
    media = resolve_media_types(monitor, opts)
    export_params = normalize_export_params(opts[:export_params])

    cond do
      Enum.empty?(channels) ->
        {:error, "No delivery targets configured for this monitor."}

      MonitorLayout.alert_widget_id(monitor, alert) == nil ->
        {:error, "Unable to resolve alert widget for export."}

      true ->
        with {:ok, exports} <-
               build_exports({:alert, monitor, alert}, media, export_params, opts),
             results <-
               deliver_to_channels(
                 monitor,
                 alert,
                 channels,
                 exports,
                 export_params,
                 opts
               ) do
          finalize_results(results, media)
        end
    end
  end

  defp resolve_media_types(%Monitor{} = monitor, opts) do
    media_types = Keyword.get(opts, :media_types, [])

    case Monitors.delivery_media_from_types(List.wrap(media_types), []) do
      {media, _invalid} when media != [] ->
        media

      _ ->
        monitor
        |> Map.get(:delivery_media, [])
        |> Monitors.delivery_media_types_from_media()
        |> case do
          [] -> @default_media
          list -> list
        end
    end
  end

  defp normalize_export_params(nil), do: %{}
  defp normalize_export_params(%{} = params), do: params
  defp normalize_export_params(params) when is_list(params), do: Enum.into(params, %{})
  defp normalize_export_params(_), do: %{}

  defp build_exports({:monitor, monitor}, media, params, opts) do
    layout_builder = layout_builder(opts)
    exporter = exporter(opts)
    exporter_opts = Keyword.get(opts, :exporter_opts, [])

    Enum.reduce_while(media, {:ok, []}, fn medium, {:ok, acc} ->
      case build_monitor_export(monitor, medium, params, layout_builder, exporter, exporter_opts) do
        {:ok, export} -> {:cont, {:ok, [export | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, exports} -> {:ok, Enum.reverse(exports)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_exports({:alert, monitor, alert}, media, params, opts) do
    layout_builder = layout_builder(opts)
    exporter = exporter(opts)
    exporter_opts = Keyword.get(opts, :exporter_opts, [])

    Enum.reduce_while(media, {:ok, []}, fn medium, {:ok, acc} ->
      case build_alert_export(monitor, alert, medium, params, layout_builder, exporter, exporter_opts) do
        {:ok, export} -> {:cont, {:ok, [export | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, exports} -> {:ok, Enum.reverse(exports)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_monitor_export(_monitor, medium, _params, _builder, _exporter, _opts)
       when medium not in [:pdf, :png_light, :png_dark] do
    {:error, "Unsupported delivery medium: #{inspect(medium)}"}
  end

  defp build_monitor_export(monitor, medium, params, builder, exporter, exporter_opts) do
    theme =
      case medium do
        :png_dark -> :dark
        _ -> :light
      end

    layout_opts =
      case medium do
        :pdf ->
          [
            params: params,
            theme: :light,
            viewport: @default_monitor_viewport
          ]

        _ ->
          [
            params: params,
            theme: theme
          ]
      end

    with {:ok, %Layout{} = layout} <- builder.build(monitor, layout_opts),
         {:ok, binary, content_type} <-
           export_binary(medium, layout, exporter, exporter_opts) do
      filename = build_filename(:monitor, monitor, medium)

      {:ok,
       %{
         medium: medium,
         filename: filename,
         content_type: content_type,
         binary: binary
       }}
    end
  end

  defp build_alert_export(_monitor, _alert, medium, _params, _builder, _exporter, _opts)
       when medium not in [:pdf, :png_light, :png_dark] do
    {:error, "Unsupported delivery medium: #{inspect(medium)}"}
  end

  defp build_alert_export(monitor, alert, medium, params, builder, exporter, exporter_opts) do
    widget_id = MonitorLayout.alert_widget_id(monitor, alert)

    if is_nil(widget_id) do
      {:error, "Unable to resolve alert widget for export."}
    else
      theme =
        case medium do
          :png_dark -> :dark
          _ -> :light
        end

      layout_opts =
        case medium do
          :pdf ->
            [
              params: params,
              theme: :light,
              viewport: @default_monitor_viewport
            ]

          _ ->
            [
              params: params,
              theme: theme
            ]
        end

      with {:ok, %Layout{} = layout} <- builder.build_widget(monitor, widget_id, layout_opts),
           {:ok, binary, content_type} <-
             export_binary(medium, layout, exporter, exporter_opts) do
        filename = build_filename({:alert, monitor, alert}, medium)

        {:ok,
         %{
           medium: medium,
           filename: filename,
           content_type: content_type,
           binary: binary
         }}
      end
    end
  end

  defp export_binary(:pdf, layout, exporter, opts) do
    exporter_call(exporter, :export_layout_pdf, [layout, opts])
    |> wrap_binary("application/pdf")
  end

  defp export_binary(medium, layout, exporter, opts) when medium in [:png_light, :png_dark] do
    exporter_call(exporter, :export_layout_png, [layout, opts])
    |> wrap_binary("image/png")
  end

  defp exporter_call(module, function, [layout, []]) do
    Kernel.apply(module, function, [layout])
  end

  defp exporter_call(module, function, [layout, opts]) do
    Kernel.apply(module, function, [layout, opts])
  end

  defp wrap_binary({:ok, binary}, content_type) when is_binary(binary) do
    {:ok, binary, content_type}
  end

  defp wrap_binary({:error, reason}, _content_type), do: {:error, format_error(reason)}

  defp deliver_to_channels(monitor, alert, channels, exports, params, opts) do
    Enum.reduce(channels, %{successes: [], failures: []}, fn channel, acc ->
      case deliver_channel(monitor, alert, channel, exports, params, opts) do
        {:ok, info} ->
          %{acc | successes: [info | acc.successes]}

        {:error, info} ->
          %{acc | failures: [info | acc.failures]}
      end
    end)
    |> Map.update!(:successes, &Enum.reverse/1)
    |> Map.update!(:failures, &Enum.reverse/1)
  end

  defp deliver_channel(monitor, alert, channel, exports, params, opts) do
    type = channel_type(channel)
    handle = channel_handle(channel)

    case type do
      :email ->
        deliver_email(monitor, alert, channel, exports, params, handle, opts)

      :slack_webhook ->
        deliver_slack(monitor, alert, channel, exports, params, handle, opts)

      :webhook ->
        {:error,
         %{
           handle: handle,
           type: :webhook,
           reason: "Webhook deliveries are not supported yet."
         }}

      :custom ->
        {:error,
         %{
           handle: handle,
           type: :custom,
           reason: "Custom deliveries are not supported yet."
         }}

      _ ->
        {:error,
         %{
           handle: handle || "unknown",
           type: type || :unknown,
           reason: "Unsupported delivery channel."
         }}
    end
  end

  defp deliver_email(monitor, alert, channel, exports, params, handle, opts) do
    recipient = channel_field(channel, :target)

    cond do
      blank?(recipient) ->
        {:error,
         %{
           handle: handle,
           type: :email,
           reason: "Delivery email address is missing."
         }}

      true ->
        mailer = mailer(opts)
        mailer_opts = Keyword.get(opts, :mailer_opts, [])

        email =
          Email.new()
          |> Email.to(recipient)
          |> Email.from(email_from(opts))
          |> Email.subject(email_subject(monitor, alert))
          |> Email.text_body(email_body(monitor, alert, params))
          |> attach_exports(exports)

        case deliver_email_with_mailer(mailer, email, mailer_opts) do
          {:ok, _meta} ->
            {:ok,
             %{
               handle: handle,
               type: :email
             }}

          {:error, reason} ->
            {:error,
             %{
               handle: handle,
               type: :email,
               reason: format_error(reason)
             }}
        end
    end
  end

  defp attach_exports(email, exports) do
    Enum.reduce(exports, email, fn export, acc ->
      attachment =
        Attachment.new({:data, export.binary},
          filename: export.filename,
          content_type: export.content_type
        )

      Email.attachment(acc, attachment)
    end)
  end

  defp deliver_email_with_mailer(mailer, email, []) do
    if function_exported?(mailer, :deliver, 1) do
      apply(mailer, :deliver, [email])
    else
      {:error, :mailer_not_configured}
    end
  end

  defp deliver_email_with_mailer(mailer, email, opts) do
    cond do
      function_exported?(mailer, :deliver, 2) -> apply(mailer, :deliver, [email, opts])
      function_exported?(mailer, :deliver, 1) -> apply(mailer, :deliver, [email])
      true -> {:error, :mailer_not_configured}
    end
  end

  defp deliver_slack(monitor, alert, channel, exports, params, handle, opts) do
    config = channel_config(channel)
    organization_id = monitor.organization_id
    installation_id = config_value(config, :installation_id)
    reference = config_value(config, :installation_reference)
    token = fetch_slack_token(organization_id, installation_id, reference)
    slack_client = slack_client(opts)
    slack_opts = Keyword.get(opts, :slack_client_opts, [])
    channel_id = config_value(config, :channel_id) || channel_field(channel, :target)

    cond do
      blank?(token) ->
        {:error,
         %{
           handle: handle,
           type: :slack_webhook,
           reason: "Slack installation is missing a bot token."
         }}

      blank?(channel_id) ->
        {:error,
         %{
           handle: handle,
           type: :slack_webhook,
           reason: "Slack channel identifier is missing."
         }}

      true ->
        message = slack_message(monitor, alert, params)

        with {:ok, _} <- slack_client.chat_post_message(token, channel_id, message, slack_opts),
             :ok <-
               upload_slack_exports(
                 slack_client,
                 token,
                 channel_id,
                 exports,
                 monitor,
                 alert,
                 slack_opts
               ) do
          {:ok,
           %{
             handle: handle,
             type: :slack_webhook
           }}
        else
          {:error, reason} ->
            {:error,
             %{
               handle: handle,
               type: :slack_webhook,
               reason: format_error(reason)
             }}
        end
    end
  end

  defp upload_slack_exports(_client, _token, _channel_id, [], _monitor, _alert, _opts), do: :ok

  defp upload_slack_exports(client, token, channel_id, exports, monitor, alert, opts) do
    Enum.reduce_while(Enum.with_index(exports, 1), :ok, fn {export, index}, :ok ->
      comment = if index == 1, do: nil, else: nil
      title = slack_export_title(monitor, alert, export)

      case client.upload_file(
             token,
             channel_id,
             export.binary,
             %{
               filename: export.filename,
               content_type: export.content_type,
               title: title,
               initial_comment: comment
             },
             opts
           ) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp finalize_results(%{successes: [], failures: failures}, _media) do
    {:error, failure_summary(failures)}
  end

  defp finalize_results(%{successes: successes, failures: failures} = results, media) do
    {:ok, Map.merge(results, %{media: media, summary: success_summary(successes, failures)})}
  end

  defp success_summary(successes, failures) do
    success_handles =
      successes
      |> Enum.map(& &1.handle)
      |> Enum.join(", ")

    failure_handles =
      failures
      |> Enum.map(fn failure -> "#{failure.handle} (#{failure.reason})" end)
      |> Enum.join(", ")

    %{
      successes: success_handles,
      failures: failure_handles
    }
  end

  defp failure_summary(failures) do
    details =
      failures
      |> Enum.map(fn failure ->
        handle = failure.handle || "unknown destination"
        "#{handle}: #{failure.reason}"
      end)
      |> Enum.join("; ")

    "Delivery failed: #{details}"
  end

  defp exporter(opts), do: Keyword.get(opts, :exporter, ChromeExporter)
  defp layout_builder(opts), do: Keyword.get(opts, :layout_builder, MonitorLayout)
  defp mailer(opts), do: Keyword.get(opts, :mailer, Mailer)
  defp slack_client(opts), do: Keyword.get(opts, :slack_client, SlackClient)

  defp email_from(opts) do
    case Keyword.get(opts, :from) || Application.get_env(:trifle, :monitor_delivery_from) do
      {name, address} when is_binary(address) -> {name, address}
      address when is_binary(address) -> {"Trifle Reports", address}
      _ -> {"Trifle Reports", "contact@example.com"}
    end
  end

  defp email_subject(%Monitor{} = monitor, nil) do
    "Monitor preview · #{monitor.name}"
  end

  defp email_subject(%Monitor{} = monitor, %Alert{} = alert) do
    label = MonitorLayout.alert_label(alert) || "Alert"
    "Alert preview · #{monitor.name} · #{label}"
  end

  defp email_body(%Monitor{} = monitor, nil, params) do
    timeframe = timeframe_label(params)

    [
      "Heads-up! Here's the latest snapshot for #{monitor.name}.",
      (if timeframe, do: "Window: #{timeframe}", else: nil),
      "",
      "Preview attached. — Trifle"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp email_body(%Monitor{} = monitor, %Alert{} = alert, params) do
    label = MonitorLayout.alert_label(alert) || "Alert"
    timeframe = timeframe_label(params)

    [
      "Quick pulse on #{monitor.name} · #{label}.",
      (if timeframe, do: "Window: #{timeframe}", else: nil),
      "",
      "Preview attached. — Trifle"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp slack_message(%Monitor{} = monitor, nil, params) do
    timeframe = timeframe_label(params)

    cond do
      timeframe ->
        "Here's the #{monitor.name} snapshot for #{timeframe}. 🚀"

      true ->
        "Here's the latest #{monitor.name} snapshot. 🚀"
    end
  end

  defp slack_message(%Monitor{} = monitor, %Alert{} = alert, params) do
    label = MonitorLayout.alert_label(alert) || "Alert"
    timeframe = timeframe_label(params)

    cond do
      timeframe ->
        "Alert preview: #{label} on #{monitor.name} (#{timeframe}). ⚡"

      true ->
        "Alert preview: #{label} on #{monitor.name}. ⚡"
    end
  end

  defp slack_export_title(%Monitor{} = monitor, nil, export) do
    "#{monitor.name} · #{medium_label(export.medium)}"
  end

  defp slack_export_title(%Monitor{} = monitor, %Alert{} = alert, export) do
    label = MonitorLayout.alert_label(alert) || "Alert"
    "#{monitor.name} · #{label} · #{medium_label(export.medium)}"
  end

  defp medium_label(:pdf), do: "PDF"
  defp medium_label(:png_light), do: "PNG (light)"
  defp medium_label(:png_dark), do: "PNG (dark)"
  defp medium_label(other), do: to_string(other)

  defp timeframe_label(params) when is_map(params) do
    timeframe =
      params
      |> Map.get("timeframe") ||
        params
        |> Map.get(:timeframe)

    from = params |> Map.get("from") || Map.get(params, :from)
    to = params |> Map.get("to") || Map.get(params, :to)

    cond do
      present?(from) && present?(to) ->
        "#{format_datetime(from)} – #{format_datetime(to)}"

      present?(timeframe) ->
        timeframe

      true ->
        nil
    end
  end

  defp timeframe_label(_), do: nil

  defp format_datetime(%DateTime{} = dt) do
    dt |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp format_datetime(value) when is_binary(value) do
    value
    |> String.split(~r/[T ]/)
    |> Enum.take(2)
    |> Enum.join(" ")
  end

  defp format_datetime(value), do: to_string(value)

  defp build_filename(:monitor, %Monitor{} = monitor, medium) do
    slug = slugify(monitor.name || "monitor")
    timestamp = current_timestamp()
    suffix =
      case medium do
        :pdf -> "preview"
        :png_light -> "preview-light"
        :png_dark -> "preview-dark"
        other -> "preview-#{other}"
      end

    ext =
      case medium do
        :pdf -> ".pdf"
        _ -> ".png"
      end

    "#{slug}-#{suffix}-#{timestamp}#{ext}"
  end

  defp build_filename({:alert, monitor, alert}, medium) do
    monitor_slug = slugify(monitor.name || "monitor")
    alert_slug = slugify(MonitorLayout.alert_label(alert) || "alert")
    timestamp = current_timestamp()
    suffix =
      case medium do
        :pdf -> "preview"
        :png_light -> "preview-light"
        :png_dark -> "preview-dark"
        other -> "preview-#{other}"
      end

    ext =
      case medium do
        :pdf -> ".pdf"
        _ -> ".png"
      end

    "#{monitor_slug}-#{alert_slug}-#{suffix}-#{timestamp}#{ext}"
  end

  defp current_timestamp do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(:basic)
  end

  defp slugify(nil), do: "monitor"

  defp slugify(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "monitor"
      slug -> slug
    end
  end

  defp slugify(value), do: value |> to_string() |> slugify()

  defp channel_type(channel) do
    value = channel_field(channel, :channel)

    cond do
      is_atom(value) ->
        value

      is_binary(value) ->
        normalized = String.replace(value, "-", "_")

        try do
          String.to_existing_atom(normalized)
        rescue
          ArgumentError -> String.to_atom(normalized)
        end

      true ->
        nil
    end
  end

  defp channel_handle(channel) do
    channel
    |> List.wrap()
    |> Monitors.delivery_handles_from_channels()
    |> List.first()
  end

  defp channel_field(channel, key) when is_atom(key) do
    Map.get(channel, key) ||
      Map.get(channel, Atom.to_string(key))
  end

  defp channel_config(channel) do
    Map.get(channel, :config) ||
      Map.get(channel, "config") ||
      %{}
  end

  defp config_value(config, key) do
    Map.get(config, key) ||
      Map.get(config, Atom.to_string(key))
  end

  defp fetch_slack_token(_organization_id, nil, nil), do: nil

  defp fetch_slack_token(organization_id, installation_id, _reference) when is_binary(installation_id) do
    case Integrations.get_slack_installation(organization_id, installation_id) do
      %{bot_access_token: token} -> token
      _ -> nil
    end
  end

  defp fetch_slack_token(organization_id, _installation_id, reference) when is_binary(reference) do
    organization_id
    |> Integrations.list_slack_installations_for_org()
    |> Enum.find(fn installation -> installation.reference == reference end)
    |> case do
      %{bot_access_token: token} -> token
      _ -> nil
    end
  end

  defp fetch_slack_token(_, _, _), do: nil

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(value) when value in [nil, []], do: true
  defp blank?(_), do: false

  defp present?(value), do: !blank?(value)

  defp format_error({:slack_error, error}), do: "Slack error: #{inspect(error)}"
  defp format_error({:slack_error, error, _payload}), do: "Slack error: #{inspect(error)}"
  defp format_error({:mailer_error, reason}), do: "Mailer error: #{inspect(reason)}"
  defp format_error({:http_error, %{status: status}}), do: "HTTP error #{status}"
  defp format_error({:error, reason}), do: format_error(reason)
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
