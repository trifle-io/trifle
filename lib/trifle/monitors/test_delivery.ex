defmodule Trifle.Monitors.TestDelivery do
  @moduledoc false

  require Logger

  alias Trifle.Integrations
  alias Trifle.Integrations.Slack.Client, as: SlackClient
  alias Trifle.Monitors
  alias Trifle.Monitors.{Alert, Monitor}
  alias Trifle.Exports.Series, as: SeriesExport
  alias TrifleApp.Exports.MonitorLayout
  alias TrifleApp.Exporters.ChromeExporter
  alias TrifleApp.Exporters.ExportLog
  alias TrifleApp.Exports.Layout
  alias Trifle.Mailer
  alias Swoosh.Attachment
  alias Swoosh.Email
  alias Mint.TransportError

  @default_media [:pdf]
  @supported_media [:pdf, :png_light, :png_dark, :file_csv, :file_json]
  @default_monitor_viewport %{width: 1920, height: 1080}
  @trigger_types [:triggered, :previewed, :recovered]

  @spec deliver_monitor(Monitor.t(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def deliver_monitor(%Monitor{} = monitor, opts \\ []) do
    channels = monitor.delivery_channels || []
    media = resolve_media_types(monitor, opts)
    export_params = normalize_export_params(opts[:export_params])

    base_context =
      monitor_log_context(monitor)
      |> Map.merge(timeframe_context(export_params))

    base_exporter_opts =
      opts
      |> Keyword.get(:exporter_opts, [])
      |> put_export_log_context(base_context)

    log_context = Keyword.get(base_exporter_opts, :log_context, %{})
    log_label = ExportLog.label(log_context)
    opts = Keyword.put(opts, :exporter_opts, base_exporter_opts)

    cond do
      Enum.empty?(channels) ->
        {:error, "No delivery targets configured for this monitor."}

      true ->
        Logger.info(
          "[monitor_export #{log_label}] deliver_monitor start channels=#{length(channels)} media=#{inspect(media)} params=#{describe_export_params(export_params)}"
        )

        case build_exports({:monitor, monitor}, media, export_params, opts) do
          {:ok, exports} ->
            Logger.info(
              "[monitor_export #{log_label}] exports_built count=#{length(exports)} media=#{inspect(Enum.map(exports, & &1.medium))}"
            )

            results =
              deliver_to_channels(
                monitor,
                nil,
                channels,
                exports,
                export_params,
                opts
              )

            log_delivery_summary(log_label, results)
            finalize_results(results, media)

          {:error, reason} ->
            Logger.error(
              "[monitor_export #{log_label}] build_exports_failed reason=#{inspect(reason)}"
            )

            {:error, reason}
        end
    end
  end

  @spec deliver_alert(Monitor.t(), Alert.t(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def deliver_alert(%Monitor{} = monitor, %Alert{} = alert, opts \\ []) do
    channels = monitor.delivery_channels || []
    media = resolve_media_types(monitor, opts)
    export_params = normalize_export_params(opts[:export_params])

    base_context =
      alert_log_context(monitor, alert)
      |> Map.merge(timeframe_context(export_params))

    base_exporter_opts =
      opts
      |> Keyword.get(:exporter_opts, [])
      |> put_export_log_context(base_context)

    log_context = Keyword.get(base_exporter_opts, :log_context, %{})
    log_label = ExportLog.label(log_context)

    opts =
      opts
      |> Keyword.put(:exporter_opts, base_exporter_opts)
      |> Keyword.update(:trigger_type, :triggered, &normalize_trigger_type/1)

    cond do
      Enum.empty?(channels) ->
        {:error, "No delivery targets configured for this monitor."}

      MonitorLayout.alert_widget_id(monitor, alert) == nil ->
        {:error, "Unable to resolve alert widget for export."}

      true ->
        Logger.info(
          "[monitor_export #{log_label}] deliver_alert start channels=#{length(channels)} media=#{inspect(media)} params=#{describe_export_params(export_params)}"
        )

        case build_exports({:alert, monitor, alert}, media, export_params, opts) do
          {:ok, exports} ->
            Logger.info(
              "[monitor_export #{log_label}] alert_exports_built count=#{length(exports)} media=#{inspect(Enum.map(exports, & &1.medium))}"
            )

            results =
              deliver_to_channels(
                monitor,
                alert,
                channels,
                exports,
                export_params,
                opts
              )

            log_delivery_summary(log_label, results)
            finalize_results(results, media)

          {:error, reason} ->
            Logger.error(
              "[monitor_export #{log_label}] alert_exports_failed reason=#{inspect(reason)}"
            )

            {:error, reason}
        end
    end
  end

  defp resolve_media_types(%Monitor{} = monitor, opts) do
    media_types = Keyword.get(opts, :media_types, [])

    case Monitors.delivery_media_from_types(List.wrap(media_types), []) do
      {media, _invalid} when media != [] ->
        media_atoms = Monitors.delivery_media_types_from_media(media)

        case media_atoms do
          [] -> fallback_media(monitor)
          list -> list
        end

      _ ->
        fallback_media(monitor)
    end
  end

  defp fallback_media(%Monitor{} = monitor) do
    monitor
    |> Map.get(:delivery_media, [])
    |> Monitors.delivery_media_types_from_media()
    |> case do
      [] -> @default_media
      list -> list
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
      medium_opts = put_export_log_context(exporter_opts, %{medium: medium})
      log_context = Keyword.get(medium_opts, :log_context, %{})
      log_label = ExportLog.label(log_context)

      Logger.info("[monitor_export #{log_label}] build_monitor_export start medium=#{medium}")

      case build_monitor_export(monitor, medium, params, layout_builder, exporter, medium_opts) do
        {:ok, export} ->
          Logger.info(
            "[monitor_export #{log_label}] build_monitor_export success medium=#{medium}"
          )

          {:cont, {:ok, [export | acc]}}

        {:error, reason} ->
          Logger.error(
            "[monitor_export #{log_label}] build_monitor_export failed medium=#{medium} reason=#{inspect(reason)}"
          )

          {:halt, {:error, reason}}
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
      medium_opts = put_export_log_context(exporter_opts, %{medium: medium})
      log_context = Keyword.get(medium_opts, :log_context, %{})
      log_label = ExportLog.label(log_context)

      Logger.info("[monitor_export #{log_label}] build_alert_export start medium=#{medium}")

      case build_alert_export(
             monitor,
             alert,
             medium,
             params,
             layout_builder,
             exporter,
             medium_opts
           ) do
        {:ok, export} ->
          Logger.info("[monitor_export #{log_label}] build_alert_export success medium=#{medium}")

          {:cont, {:ok, [export | acc]}}

        {:error, reason} ->
          Logger.error(
            "[monitor_export #{log_label}] build_alert_export failed medium=#{medium} reason=#{inspect(reason)}"
          )

          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, exports} -> {:ok, Enum.reverse(exports)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_monitor_export(_monitor, medium, _params, _builder, _exporter, _opts)
       when medium not in @supported_media do
    {:error, "Unsupported delivery medium: #{inspect(medium)}"}
  end

  defp build_monitor_export(monitor, medium, params, builder, _exporter, _opts)
       when medium in [:file_csv, :file_json] do
    opts = [params: params]

    with {:ok, %{export: export}} <- resolve_series_export(builder, monitor, opts),
         {:ok, binary, content_type} <- encode_series_export(medium, export) do
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

  defp build_monitor_export(monitor, medium, params, builder, exporter, exporter_opts) do
    log_context = Keyword.get(exporter_opts, :log_context, %{})
    log_label = ExportLog.label(log_context)

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

    Logger.info(
      "[monitor_export #{log_label}] layout_build start medium=#{medium} theme=#{theme}"
    )

    case builder.build(monitor, layout_opts) do
      {:ok, %Layout{} = layout} ->
        Logger.info("[monitor_export #{log_label}] layout_build success layout_id=#{layout.id}")

        case export_binary(medium, layout, exporter, exporter_opts) do
          {:ok, binary, content_type} ->
            Logger.info(
              "[monitor_export #{log_label}] export_binary success medium=#{medium} bytes=#{byte_size(binary)}"
            )

            filename = build_filename(:monitor, monitor, medium)

            {:ok,
             %{
               medium: medium,
               filename: filename,
               content_type: content_type,
               binary: binary
             }}

          {:error, reason} ->
            Logger.error(
              "[monitor_export #{log_label}] export_binary failed medium=#{medium} reason=#{inspect(reason)}"
            )

            {:error, reason}
        end

      {:error, reason} ->
        Logger.error(
          "[monitor_export #{log_label}] layout_build failed medium=#{medium} reason=#{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp build_alert_export(_monitor, _alert, medium, _params, _builder, _exporter, _opts)
       when medium not in @supported_media do
    {:error, "Unsupported delivery medium: #{inspect(medium)}"}
  end

  defp build_alert_export(monitor, alert, medium, params, builder, _exporter, _opts)
       when medium in [:file_csv, :file_json] do
    opts = [params: params]

    with {:ok, %{export: export}} <- resolve_series_export(builder, monitor, opts),
         {:ok, binary, content_type} <- encode_series_export(medium, export) do
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

  defp build_alert_export(monitor, alert, medium, params, builder, exporter, exporter_opts) do
    log_context = Keyword.get(exporter_opts, :log_context, %{})
    log_label = ExportLog.label(log_context)
    widget_id = MonitorLayout.alert_widget_id(monitor, alert)

    if is_nil(widget_id) do
      Logger.error("[monitor_export #{log_label}] alert_widget_missing medium=#{medium}")

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

      Logger.info(
        "[monitor_export #{log_label}] alert_layout_build start medium=#{medium} widget=#{widget_id} theme=#{theme}"
      )

      case builder.build_widget(monitor, widget_id, layout_opts) do
        {:ok, %Layout{} = layout} ->
          Logger.info(
            "[monitor_export #{log_label}] alert_layout_build success layout_id=#{layout.id}"
          )

          case export_binary(medium, layout, exporter, exporter_opts) do
            {:ok, binary, content_type} ->
              Logger.info(
                "[monitor_export #{log_label}] alert_export_binary success medium=#{medium} bytes=#{byte_size(binary)}"
              )

              filename = build_filename({:alert, monitor, alert}, medium)

              {:ok,
               %{
                 medium: medium,
                 filename: filename,
                 content_type: content_type,
                 binary: binary
               }}

            {:error, reason} ->
              Logger.error(
                "[monitor_export #{log_label}] alert_export_binary failed medium=#{medium} reason=#{inspect(reason)}"
              )

              {:error, reason}
          end

        {:error, reason} ->
          Logger.error(
            "[monitor_export #{log_label}] alert_layout_build failed medium=#{medium} widget=#{widget_id} reason=#{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  end

  defp resolve_series_export(builder, monitor, opts) do
    cond do
      function_exported?(builder, :series_export, 2) ->
        builder.series_export(monitor, opts)

      true ->
        MonitorLayout.series_export(monitor, opts)
    end
  end

  defp encode_series_export(:file_csv, export) do
    {:ok, SeriesExport.to_csv(export), "text/csv"}
  end

  defp encode_series_export(:file_json, export) do
    {:ok, SeriesExport.to_json(export), "application/json"}
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

  defp put_export_log_context(exporter_opts, context) do
    merged =
      exporter_opts
      |> Keyword.get(:log_context, %{})
      |> ExportLog.normalize()
      |> Map.merge(ExportLog.normalize(context))

    Keyword.put(exporter_opts, :log_context, merged)
  end

  defp monitor_log_context(%Monitor{} = monitor) do
    %{
      export_scope: :monitor,
      monitor_id: monitor.id,
      monitor_slug: Map.get(monitor, :slug),
      monitor_name: Map.get(monitor, :name)
    }
  end

  defp alert_log_context(%Monitor{} = monitor, %Alert{} = alert) do
    monitor_log_context(monitor)
    |> Map.put(:export_scope, :alert)
    |> maybe_put_value(:alert_id, alert.id)
    |> maybe_put_value(:alert_strategy, Map.get(alert, :analysis_strategy))
  end

  defp timeframe_context(%{} = params) do
    %{}
    |> maybe_put_value(:export_from, Map.get(params, :from))
    |> maybe_put_value(:export_to, Map.get(params, :to))
    |> maybe_put_value(:export_display, Map.get(params, :display))
    |> maybe_put_value(:export_granularity, Map.get(params, :granularity))
  end

  defp timeframe_context(_), do: %{}

  defp maybe_put_value(map, _key, nil), do: map
  defp maybe_put_value(map, _key, ""), do: map
  defp maybe_put_value(map, key, value), do: Map.put(map, key, value)

  defp describe_export_params(%{display: display, from: from, to: to} = params) do
    window =
      params
      |> Map.get(:window)
      |> case do
        nil -> ""
        val -> " window=#{inspect(val)}"
      end

    "display=#{display} from=#{format_timestamp(from)} to=#{format_timestamp(to)}#{window}"
  end

  defp describe_export_params(%{} = params) when map_size(params) > 0 do
    keys = params |> Map.keys() |> Enum.map(&to_string/1) |> Enum.join(",")
    "keys=#{keys}"
  end

  defp describe_export_params(_), do: "none"

  defp format_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_timestamp(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_timestamp(%Date{} = date), do: Date.to_iso8601(date)
  defp format_timestamp(nil), do: "nil"
  defp format_timestamp(other) when is_binary(other), do: other
  defp format_timestamp(other), do: inspect(other)

  defp log_delivery_summary(log_label, %{successes: successes, failures: failures}) do
    Logger.info(
      "[monitor_export #{log_label}] deliver_to_channels summary success=#{length(successes)} failure=#{length(failures)}"
    )

    Enum.each(successes, fn info ->
      Logger.debug(
        "[monitor_export #{log_label}] delivery_ok type=#{Map.get(info, :type)} handle=#{Map.get(info, :handle)}"
      )
    end)

    Enum.each(failures, fn info ->
      Logger.warning(
        "[monitor_export #{log_label}] delivery_failed type=#{Map.get(info, :type)} handle=#{Map.get(info, :handle)} reason=#{inspect(Map.get(info, :reason))}"
      )
    end)
  end

  defp delivery_trigger_type(nil, _opts), do: nil

  defp delivery_trigger_type(_alert, opts) do
    Keyword.get(opts, :trigger_type, :triggered)
  end

  defp deliver_to_channels(monitor, alert, channels, exports, params, opts) do
    log_context =
      opts
      |> Keyword.get(:exporter_opts, [])
      |> Keyword.get(:log_context, %{})

    log_label = ExportLog.label(log_context)

    Logger.info(
      "[monitor_export #{log_label}] deliver_to_channels start channel_count=#{length(channels)}"
    )

    Enum.reduce(channels, %{successes: [], failures: []}, fn channel, acc ->
      type = channel_type(channel)
      handle = channel_handle(channel)

      Logger.info(
        "[monitor_export #{log_label}] deliver_channel start type=#{type} handle=#{handle}"
      )

      case deliver_channel(monitor, alert, channel, exports, params, opts) do
        {:ok, info} ->
          Logger.info(
            "[monitor_export #{log_label}] deliver_channel success type=#{info.type} handle=#{Map.get(info, :handle)}"
          )

          %{acc | successes: [info | acc.successes]}

        {:error, info} ->
          Logger.warning(
            "[monitor_export #{log_label}] deliver_channel failure type=#{info.type} handle=#{Map.get(info, :handle)} reason=#{inspect(Map.get(info, :reason))}"
          )

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

    log_context =
      opts
      |> Keyword.get(:exporter_opts, [])
      |> Keyword.get(:log_context, %{})

    log_label = ExportLog.label(log_context)
    log_prefix = monitor_log_prefix(log_label)
    client_options = mailer_client_options(opts)
    retry_config = mailer_retry_config()

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
        attachments = email_attachments(exports)
        trigger_type = delivery_trigger_type(alert, opts)

        email =
          Email.new()
          |> Email.to(recipient)
          |> Email.from(email_from(opts))
          |> Email.subject(email_subject(monitor, alert, trigger_type))
          |> Email.text_body(email_body(monitor, alert, params, trigger_type))
          |> attach_exports(exports)
          |> put_email_client_options(client_options)

        case send_email_with_retry(
               mailer,
               email,
               mailer_opts,
               retry_config.attempts,
               retry_config.backoff_ms,
               log_prefix
             ) do
          {:ok, _meta} ->
            {:ok,
             %{
               handle: handle,
               type: :email
             }
             |> maybe_put_non_empty(:attachments, attachments)}

          {:error, reason} ->
            {:error,
             %{
               handle: handle,
               type: :email,
               reason: format_error(reason)
             }
             |> maybe_put_non_empty(:attachments, attachments)}
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

  defp email_attachments(exports) when is_list(exports) do
    exports
    |> Enum.map(&build_email_attachment/1)
    |> Enum.reject(&is_nil/1)
  end

  defp email_attachments(_), do: []

  defp build_email_attachment(export) when is_map(export) do
    export
    |> Map.take([:filename, :content_type, :medium])
    |> maybe_put_attachment_size(Map.get(export, :binary))
    |> prune_empty_values()
    |> case do
      %{} = value when map_size(value) == 0 -> nil
      value -> value
    end
  end

  defp build_email_attachment(_), do: nil

  defp maybe_put_attachment_size(map, binary) when is_binary(binary) do
    Map.put(map, :size, byte_size(binary))
  end

  defp maybe_put_attachment_size(map, _), do: map

  defp deliver_email_with_mailer(mailer, email, opts) do
    _ = Code.ensure_loaded(mailer)

    cond do
      function_exported?(mailer, :deliver, 2) -> apply(mailer, :deliver, [email, opts])
      function_exported?(mailer, :deliver, 1) -> apply(mailer, :deliver, [email])
      true -> {:error, :mailer_not_configured}
    end
  end

  defp mailer_client_options(opts) do
    defaults = Application.get_env(:trifle, :mailer_client_options, [])
    overrides = Keyword.get(opts, :mailer_client_options, [])
    Keyword.merge(defaults, overrides)
  end

  defp mailer_retry_config do
    config = Application.get_env(:trifle, :mailer_retry, attempts: 1, backoff_ms: 0)

    attempts =
      config
      |> Keyword.get(:attempts, 1)
      |> max(1)

    backoff_ms =
      config
      |> Keyword.get(:backoff_ms, 0)
      |> max(0)

    %{attempts: attempts, backoff_ms: backoff_ms}
  end

  defp put_email_client_options(%Email{} = email, []), do: email

  defp put_email_client_options(%Email{} = email, opts) do
    existing = Map.get(email.private, :client_options, [])
    merged = Keyword.merge(opts, existing)
    Email.put_private(email, :client_options, merged)
  end

  defp monitor_log_prefix(""), do: ""
  defp monitor_log_prefix(label) when is_binary(label), do: " #{label}"
  defp monitor_log_prefix(_), do: ""

  defp send_email_with_retry(mailer, email, mailer_opts, attempts, backoff_ms, log_prefix) do
    attempts = max(attempts, 1)

    do_send_email_with_retry(
      mailer,
      email,
      mailer_opts,
      attempts,
      backoff_ms,
      log_prefix,
      attempts
    )
  end

  defp do_send_email_with_retry(_mailer, _email, _mailer_opts, 0, _backoff_ms, _log_prefix, _),
    do: {:error, :retry_exhausted}

  defp do_send_email_with_retry(
         mailer,
         email,
         mailer_opts,
         attempts_left,
         backoff_ms,
         log_prefix,
         total_attempts
       ) do
    case deliver_email_with_mailer(mailer, email, mailer_opts) do
      {:ok, _} = ok ->
        ok

      {:error, %TransportError{} = reason} ->
        if attempts_left > 1 do
          Logger.warning(
            "[monitor_export#{log_prefix}] mailer_transport_timeout attempt=#{total_attempts - attempts_left + 1} remaining=#{attempts_left - 1} reason=#{inspect(reason)}"
          )

          if backoff_ms > 0 do
            Process.sleep(backoff_ms)
          end

          do_send_email_with_retry(
            mailer,
            email,
            mailer_opts,
            attempts_left - 1,
            backoff_ms,
            log_prefix,
            total_attempts
          )
        else
          {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
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

    channel_id = resolve_slack_channel_id(channel, config, monitor)

    trigger_type = delivery_trigger_type(alert, opts)

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
           reason:
             "Slack channel identifier is missing or invalid. Refresh Slack channels from Delivery settings and re-save this monitor."
         }}

      true ->
        message =
          case alert do
            nil -> slack_message(monitor, nil, params)
            %Alert{} -> slack_message(monitor, alert, params, trigger_type)
          end

        case upload_slack_exports(
               slack_client,
               token,
               channel_id,
               exports,
               monitor,
               alert,
               trigger_type,
               message,
               slack_opts
             ) do
          {:ok, %{files: attachments}} ->
            {:ok,
             %{
               handle: handle,
               type: :slack_webhook,
               attachments: attachments
             }}

          {:error, reason, attachments} ->
            {:error,
             %{
               handle: handle,
               type: :slack_webhook,
               reason: format_error(reason),
               attachments: attachments,
               error: reason
             }}
        end
    end
  end

  defp upload_slack_exports(
         _client,
         _token,
         _channel_id,
         [],
         _monitor,
         _alert,
         _trigger_type,
         _message,
         _opts
       ),
       do: {:ok, %{files: []}}

  defp upload_slack_exports(
         client,
         token,
         channel_id,
         exports,
         monitor,
         alert,
         trigger_type,
         message,
         opts
       ) do
    Enum.reduce_while(Enum.with_index(exports, 1), {:ok, []}, fn {export, index}, {:ok, acc} ->
      comment = if index == 1 && present?(message), do: message, else: nil
      title = slack_export_title(monitor, alert, export, trigger_type)

      metadata = %{
        filename: export.filename,
        content_type: export.content_type,
        title: title,
        initial_comment: comment
      }

      case client.upload_file(token, channel_id, export.binary, metadata, opts) do
        {:ok, upload} ->
          attachment = build_slack_attachment(channel_id, export, title, upload)
          {:cont, {:ok, [attachment | acc]}}

        {:error, {:slack_error, "missing_scope", payload}} ->
          {:halt, {:missing_scope, payload, acc}}

        {:error, {:slack_error, "method_deprecated", payload}} ->
          {:halt, {:method_deprecated, payload, acc}}

        {:error, {:slack_error, "invalid_arguments", payload}} ->
          {:halt, {:invalid_arguments, payload, acc}}

        {:error, {:slack_error, "not_in_channel", payload}} ->
          {:halt, {:not_in_channel, payload, acc}}

        {:error, reason} ->
          {:halt, {:error, reason, acc}}
      end
    end)
    |> finalize_slack_uploads(client, token, channel_id, message, opts)
  end

  defp maybe_post_fallback_message(_client, _token, _channel_id, message, _opts)
       when message in [nil, ""] do
    :ok
  end

  defp maybe_post_fallback_message(client, token, channel_id, message, opts) do
    case client.chat_post_message(token, channel_id, message, opts) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp finalize_slack_uploads({:ok, attachments}, _client, _token, _channel_id, _message, _opts) do
    {:ok, %{files: Enum.reverse(attachments)}}
  end

  defp finalize_slack_uploads(
         {:missing_scope, payload, attachments},
         client,
         token,
         channel_id,
         message,
         opts
       ) do
    Logger.warning(
      "Slack upload aborted (missing_scope) for channel #{channel_id}: #{inspect(payload)}"
    )

    maybe_post_fallback_message(client, token, channel_id, message, opts)
    {:error, {:slack_missing_scope, payload}, Enum.reverse(attachments)}
  end

  defp finalize_slack_uploads(
         {:method_deprecated, payload, attachments},
         client,
         token,
         channel_id,
         message,
         opts
       ) do
    Logger.warning(
      "Slack upload aborted (method_deprecated) for channel #{channel_id}: #{inspect(payload)}"
    )

    maybe_post_fallback_message(client, token, channel_id, message, opts)
    {:error, {:slack_method_deprecated, payload}, Enum.reverse(attachments)}
  end

  defp finalize_slack_uploads(
         {:invalid_arguments, payload, attachments},
         client,
         token,
         channel_id,
         message,
         opts
       ) do
    Logger.warning(
      "Slack upload rejected (invalid_arguments) for channel #{channel_id}: #{inspect(payload)}"
    )

    maybe_post_fallback_message(client, token, channel_id, message, opts)
    {:error, {:slack_error, "invalid_arguments", payload}, Enum.reverse(attachments)}
  end

  defp finalize_slack_uploads(
         {:not_in_channel, payload, attachments},
         client,
         token,
         channel_id,
         message,
         opts
       ) do
    Logger.info(
      "Slack upload failed (not_in_channel) for channel #{channel_id}: #{inspect(payload)}"
    )

    maybe_post_fallback_message(client, token, channel_id, message, opts)
    {:error, {:slack_error, "not_in_channel", payload}, Enum.reverse(attachments)}
  end

  defp finalize_slack_uploads(
         {:error, reason, attachments},
         client,
         token,
         channel_id,
         message,
         opts
       ) do
    Logger.warning("Slack upload failed for channel #{channel_id}: #{inspect(reason)}")

    maybe_post_fallback_message(client, token, channel_id, message, opts)
    {:error, reason, Enum.reverse(attachments)}
  end

  defp build_slack_attachment(channel_id, export, title, upload) do
    slack_file = sanitize_slack_file_metadata(Map.get(upload, :file))

    %{
      channel_id: channel_id,
      medium: export.medium,
      filename: export.filename,
      content_type: export.content_type,
      title: title,
      file_id: Map.get(upload, :file_id),
      slack_file: slack_file,
      permalink:
        case slack_file do
          %{} = file ->
            Map.get(file, "permalink") ||
              Map.get(file, "permalink_public") ||
              Map.get(file, "url_private")

          _ ->
            nil
        end
    }
  end

  defp sanitize_slack_file_metadata(%{} = file) do
    allowed =
      ~w(id name title mimetype filetype size permalink permalink_public url_private url_private_download)

    file
    |> Enum.filter(fn {key, _value} -> key in allowed end)
    |> Map.new()
  end

  defp sanitize_slack_file_metadata(_), do: nil

  defp finalize_results(%{successes: [], failures: failures}, _media) do
    {:error, failure_summary(failures)}
  end

  defp finalize_results(%{successes: successes, failures: failures} = results, media) do
    attachments =
      successes
      |> Enum.flat_map(fn success ->
        success
        |> Map.get(:attachments, [])
        |> Enum.map(&Map.put(&1, :handle, success.handle))
      end)

    summary = success_summary(successes, failures)

    extras =
      %{media: media, summary: summary}
      |> maybe_put_non_empty(:attachments, attachments)

    {:ok, Map.merge(results, extras)}
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

    attachments =
      successes
      |> Enum.map(fn success ->
        success
        |> Map.get(:attachments, [])
        |> case do
          [] ->
            nil

          files ->
            %{
              handle: success.handle,
              type: success.type,
              files: files
            }
            |> prune_empty_values()
        end
      end)
      |> Enum.reject(&is_nil/1)

    error_details =
      failures
      |> Enum.map(fn failure ->
        %{
          handle: failure.handle,
          type: failure.type,
          reason: failure.reason,
          error: Map.get(failure, :error),
          files: Map.get(failure, :attachments, [])
        }
        |> prune_empty_values()
      end)
      |> Enum.reject(&(&1 == %{}))

    %{
      successes: success_handles,
      failures: failure_handles
    }
    |> maybe_put_non_empty(:attachments, attachments)
    |> maybe_put_non_empty(:error_details, error_details)
  end

  defp maybe_put_non_empty(map, _key, value) when value in [nil, "", []], do: map
  defp maybe_put_non_empty(map, key, value), do: Map.put(map, key, value)

  defp prune_empty_values(map) when is_map(map) do
    map
    |> Enum.reject(fn
      {_key, value} when value in [nil, "", []] -> true
      _ -> false
    end)
    |> Map.new()
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
    default_from =
      Application.get_env(:trifle, :mailer_from, {"Trifle Reports", "contact@example.com"})

    case Keyword.get(opts, :from) ||
           Application.get_env(:trifle, :monitor_delivery_from) ||
           default_from do
      {name, address} when is_binary(name) and is_binary(address) ->
        {name, address}

      address when is_binary(address) ->
        {elem(default_from, 0), address}

      _ ->
        default_from
    end
  end

  defp email_subject(%Monitor{} = monitor, nil, _trigger_type) do
    "Monitor preview · #{monitor.name}"
  end

  defp email_subject(%Monitor{} = monitor, %Alert{} = alert, trigger_type) do
    alert_descriptor(monitor, alert, trigger_type)
  end

  defp email_body(%Monitor{} = monitor, nil, params, _trigger_type) do
    detail = window_details(params)
    window_line = window_detail_line(detail)

    [
      "Heads-up! Here's the latest snapshot for #{monitor.name}.",
      window_line,
      "",
      "Preview attached. — Trifle"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp email_body(%Monitor{} = monitor, %Alert{} = alert, params, trigger_type) do
    descriptor = alert_descriptor(monitor, alert, trigger_type)
    detail = window_details(params)
    window_line = window_detail_line(detail)

    [
      descriptor,
      window_line,
      "",
      "Snapshot attached. — Trifle"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp slack_message(%Monitor{} = monitor, nil, params) do
    detail = window_details(params)
    window_line = window_detail_line(detail)
    base = "Here's the #{monitor.name} snapshot."

    case window_line do
      nil -> base <> " 🚀"
      line -> base <> "\n" <> line <> " 🚀"
    end
  end

  defp slack_message(%Monitor{} = monitor, %Alert{} = alert, params, trigger_type) do
    detail = window_details(params)
    window_line = window_detail_line(detail)
    base = alert_descriptor(monitor, alert, trigger_type)

    case window_line do
      nil -> base
      line -> base <> "\n" <> line
    end
  end

  defp slack_export_title(%Monitor{} = monitor, nil, export, _trigger_type) do
    "#{monitor.name} · #{medium_label(export.medium)}"
  end

  defp slack_export_title(%Monitor{} = monitor, %Alert{} = alert, export, trigger_type) do
    "#{alert_descriptor(monitor, alert, trigger_type)} · #{medium_label(export.medium)}"
  end

  defp medium_label(:pdf), do: "PDF"
  defp medium_label(:png_light), do: "PNG (light)"
  defp medium_label(:png_dark), do: "PNG (dark)"
  defp medium_label(:file_csv), do: "File CSV"
  defp medium_label(:file_json), do: "File JSON"
  defp medium_label(other), do: to_string(other)

  defp normalize_trigger_type(type) when type in @trigger_types, do: type

  defp normalize_trigger_type(type) when is_binary(type) do
    case String.downcase(type) do
      "previewed" -> :previewed
      "recovered" -> :recovered
      _ -> :triggered
    end
  end

  defp normalize_trigger_type(_), do: :triggered

  defp alert_descriptor(%Monitor{} = monitor, %Alert{} = alert, trigger_type) do
    label = MonitorLayout.alert_label(alert) || "Alert"

    [
      monitor.name,
      trigger_type_label(trigger_type),
      label
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp trigger_type_label(:previewed), do: "🧪 Previewed (Test)"
  defp trigger_type_label(:recovered), do: "✅ Recovered"
  defp trigger_type_label(:triggered), do: "🚨 Triggered"
  defp trigger_type_label(_), do: "🚨 Triggered"

  defp window_details(params) when is_map(params) do
    timeframe = fetch_param(params, "timeframe")

    cond do
      window = window_label_from_params(params) -> {:window, window}
      present?(timeframe) -> {:timeframe, timeframe}
      true -> nil
    end
  end

  defp window_details(_), do: nil

  defp window_label_from_params(params) when is_map(params) do
    from = fetch_param(params, "from")
    to = fetch_param(params, "to")

    cond do
      present?(from) && present?(to) ->
        "#{format_datetime(from)} → #{format_datetime(to)}"

      true ->
        nil
    end
  end

  defp window_label_from_params(_), do: nil

  defp window_detail_line({:window, value}), do: "Window: #{value}"
  defp window_detail_line({:timeframe, value}), do: "Window: #{value}"
  defp window_detail_line(_), do: nil

  defp fetch_param(params, key) when is_map(params) do
    Map.get(params, key) ||
      case key do
        binary when is_binary(binary) ->
          case existing_atom(binary) do
            nil -> nil
            atom_key -> Map.get(params, atom_key)
          end

        atom when is_atom(atom) ->
          Map.get(params, Atom.to_string(atom))

        _ ->
          nil
      end
  end

  defp fetch_param(_params, _key), do: nil

  defp existing_atom(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> nil
    end
  end

  defp existing_atom(_), do: nil

  defp format_datetime(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  rescue
    _ -> DateTime.to_iso8601(dt)
  end

  defp format_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} ->
        format_datetime(dt)

      {:error, _} ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive} ->
            naive
            |> NaiveDateTime.truncate(:second)
            |> Calendar.strftime("%Y-%m-%d %H:%M:%S")

          {:error, _} ->
            value
        end
    end
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
        :file_csv -> "data-table"
        :file_json -> "data-raw"
        other -> "preview-#{other}"
      end

    ext =
      case medium do
        :pdf -> ".pdf"
        :file_csv -> ".csv"
        :file_json -> ".json"
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
        :file_csv -> "data-table"
        :file_json -> "data-raw"
        other -> "preview-#{other}"
      end

    ext =
      case medium do
        :pdf -> ".pdf"
        :file_csv -> ".csv"
        :file_json -> ".json"
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

  defp fetch_slack_token(organization_id, installation_id, _reference)
       when is_binary(installation_id) do
    case Integrations.get_slack_installation(organization_id, installation_id) do
      %{bot_access_token: token} -> token
      _ -> nil
    end
  end

  defp fetch_slack_token(organization_id, _installation_id, reference)
       when is_binary(reference) do
    organization_id
    |> Integrations.list_slack_installations_for_org()
    |> Enum.find(fn installation -> installation.reference == reference end)
    |> case do
      %{bot_access_token: token} -> token
      _ -> nil
    end
  end

  defp fetch_slack_token(_, _, _), do: nil

  defp resolve_slack_channel_id(channel, config, %Monitor{} = monitor) do
    candidates = [
      channel_field(channel, :target),
      config_value(config, :slack_channel_id),
      config_value(config, :channel_slack_id)
    ]

    case Enum.find(candidates, &valid_slack_channel_id?/1) do
      nil ->
        fallback_slack_channel_id(channel, config, monitor)

      id ->
        id
    end
  end

  defp fallback_slack_channel_id(channel, config, %Monitor{} = monitor) do
    channel_db_id =
      config_value(config, :channel_id) ||
        config_value(config, :channel_db_id)

    cond do
      valid_slack_channel_id?(channel_db_id) ->
        channel_db_id

      is_binary(channel_db_id) ->
        fetch_slack_channel_id_from_db(
          monitor.organization_id,
          channel_db_id,
          config_value(config, :installation_id)
        )

      true ->
        case parse_slack_handle(channel_handle(channel)) do
          {reference, channel_name} ->
            fetch_slack_channel_id_by_name(monitor.organization_id, reference, channel_name)

          _ ->
            nil
        end
    end
  end

  defp fetch_slack_channel_id_from_db(_organization_id, nil, _installation_id), do: nil

  defp fetch_slack_channel_id_from_db(organization_id, channel_db_id, installation_id) do
    installations =
      cond do
        valid_slack_channel_id?(channel_db_id) ->
          []

        present?(installation_id) ->
          case Integrations.get_slack_installation(
                 organization_id,
                 installation_id,
                 preload_channels: true
               ) do
            nil -> []
            installation -> [installation]
          end

        true ->
          Integrations.list_slack_installations_for_org(organization_id, preload_channels: true)
      end

    installations
    |> Enum.find_value(fn installation ->
      installation.channels
      |> List.wrap()
      |> Enum.find_value(fn slack_channel ->
        cond do
          slack_channel.id == channel_db_id ->
            slack_channel.channel_id

          slack_channel.channel_id == channel_db_id ->
            slack_channel.channel_id

          true ->
            nil
        end
      end)
    end)
  end

  defp fetch_slack_channel_id_by_name(organization_id, reference, channel_name)
       when is_binary(reference) and is_binary(channel_name) do
    Integrations.list_slack_installations_for_org(organization_id, preload_channels: true)
    |> Enum.find_value(fn installation ->
      if installation.reference == reference do
        installation.channels
        |> List.wrap()
        |> Enum.find_value(fn slack_channel ->
          if channel_name_matches?(slack_channel.name, channel_name) do
            slack_channel.channel_id
          else
            nil
          end
        end)
      end
    end)
  end

  defp fetch_slack_channel_id_by_name(_, _, _), do: nil

  defp parse_slack_handle(handle) when is_binary(handle) do
    case String.split(handle, "#", parts: 2) do
      [reference, channel_name] when reference != "" and channel_name != "" ->
        {reference, channel_name}

      _ ->
        nil
    end
  end

  defp parse_slack_handle(_), do: nil

  defp channel_name_matches?(a, b) when is_binary(a) and is_binary(b) do
    normalize_channel_name(a) == normalize_channel_name(b)
  end

  defp channel_name_matches?(_, _), do: false

  defp normalize_channel_name(name) do
    name
    |> String.trim()
    |> String.trim_leading("#")
    |> String.downcase()
  end

  defp valid_slack_channel_id?(value) when is_binary(value) do
    trimmed = String.trim(value)

    trimmed != "" and
      String.length(trimmed) >= 8 and
      Regex.match?(~r/^[A-Z0-9]+$/, trimmed)
  end

  defp valid_slack_channel_id?(_), do: false

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(value) when value in [nil, []], do: true
  defp blank?(_), do: false

  defp present?(value), do: !blank?(value)

  defp format_error({:slack_missing_scope, _payload}),
    do:
      "Slack workspace is missing permission to upload files (files:write). Reconnect Slack from Delivery settings to grant it."

  defp format_error({:slack_error, "missing_scope"}),
    do: "Slack error: missing files:write scope."

  defp format_error({:slack_error, "missing_scope", _payload}),
    do: "Slack error: missing files:write scope."

  defp format_error({:slack_method_deprecated, _payload}),
    do:
      "Slack API rejected the upload (method deprecated). Reconnect Slack or update the app scopes to enable file uploads."

  defp format_error({:slack_error, "method_deprecated"}),
    do:
      "Slack API rejected the upload (method deprecated). Reconnect Slack or update the app scopes to enable file uploads."

  defp format_error({:slack_error, "method_deprecated", _payload}),
    do:
      "Slack API rejected the upload (method deprecated). Reconnect Slack or update the app scopes to enable file uploads."

  defp format_error({:slack_error, "not_in_channel"}),
    do: "Slack app is not a member of that channel. Invite the Trifle bot (e.g. /invite @Trifle)."

  defp format_error({:slack_error, "not_in_channel", _payload}),
    do: "Slack app is not a member of that channel. Invite the Trifle bot (e.g. /invite @Trifle)."

  defp format_error({:slack_error, "invalid_arguments", payload}) do
    detail =
      payload
      |> slack_invalid_argument_detail()
      |> case do
        nil -> ""
        message -> " (#{message})"
      end

    "Slack rejected the upload due to invalid arguments#{detail}."
  end

  defp format_error({:slack_error, error}), do: "Slack error: #{inspect(error)}"

  defp format_error({:slack_error, error, _payload}), do: "Slack error: #{inspect(error)}"
  defp format_error({:mailer_error, reason}), do: "Mailer error: #{inspect(reason)}"

  defp format_error(:mailer_not_configured),
    do:
      "Email delivery is not configured. Update Trifle.Mailer settings (see EMAILS.md) and try again."

  defp format_error({:http_error, %{status: status}}), do: "HTTP error #{status}"

  defp format_error({:upload_failed, %{status: status, body: body}})
       when is_binary(body) and body != "" do
    preview = String.slice(body, 0, 180)
    "Slack storage upload failed (HTTP #{status}): #{preview}"
  end

  defp format_error({:upload_failed, %{status: status}}),
    do: "Slack storage upload failed (HTTP #{status})."

  defp format_error({:upload_failed, details}),
    do: "Slack storage upload failed: #{inspect(details)}"

  defp format_error({:error, reason}), do: format_error(reason)
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp slack_invalid_argument_detail(%{"errors" => [first | _]}) when is_binary(first) do
    case first do
      "channel_ids" -> "channel selection missing or invalid"
      "channel_id" -> "channel ID missing or invalid"
      "files" -> "file payload missing required fields"
      other -> other
    end
  end

  defp slack_invalid_argument_detail(%{"errors" => errors}) when is_list(errors) do
    errors
    |> Enum.map(&to_string/1)
    |> Enum.join(", ")
  end

  defp slack_invalid_argument_detail(_), do: nil
end
