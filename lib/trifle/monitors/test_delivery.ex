defmodule Trifle.Monitors.TestDelivery do
  @moduledoc false

  require Logger

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
      case build_alert_export(
             monitor,
             alert,
             medium,
             params,
             layout_builder,
             exporter,
             exporter_opts
           ) do
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

    channel_id = resolve_slack_channel_id(channel, config, monitor)

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
        message = slack_message(monitor, alert, params)

        case upload_slack_exports(
               slack_client,
               token,
               channel_id,
               exports,
               monitor,
               alert,
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

  defp upload_slack_exports(_client, _token, _channel_id, [], _monitor, _alert, _message, _opts),
    do: {:ok, %{files: []}}

  defp upload_slack_exports(client, token, channel_id, exports, monitor, alert, message, opts) do
    Enum.reduce_while(Enum.with_index(exports, 1), {:ok, []}, fn {export, index}, {:ok, acc} ->
      comment = if index == 1 && present?(message), do: message, else: nil
      title = slack_export_title(monitor, alert, export)

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
    Logger.warning(
      "Slack upload failed for channel #{channel_id}: #{inspect(reason)}"
    )

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

  defp email_body(%Monitor{} = monitor, %Alert{} = alert, params) do
    label = MonitorLayout.alert_label(alert) || "Alert"
    detail = window_details(params)
    window_line = window_detail_line(detail)

    [
      "Quick pulse on #{monitor.name} · #{label}.",
      window_line,
      "",
      "Preview attached. — Trifle"
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

  defp slack_message(%Monitor{} = monitor, %Alert{} = alert, params) do
    label = MonitorLayout.alert_label(alert) || "Alert"
    detail = window_details(params)
    window_line = window_detail_line(detail)
    base = "Alert preview: #{label} on #{monitor.name}."

    case window_line do
      nil -> base <> " ⚡"
      line -> base <> "\n" <> line <> " ⚡"
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
    |> DateTime.truncate(:minute)
    |> Calendar.strftime("%Y-%m-%d %H:%M %Z")
  rescue
    _ -> DateTime.to_iso8601(dt)
  end

  defp format_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> format_datetime(dt)
      {:error, _} -> value
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
