defmodule TrifleApp.Components.DashboardWidgets.WidgetView do
  @moduledoc false

  use TrifleApp, :html

  alias TrifleApp.Components.DashboardWidgets.Text, as: TextWidgets
  alias TrifleApp.DesignSystem.ChartColors

  attr :dashboard, :map, required: true
  attr :stats, :any, default: nil
  attr :print_mode, :boolean, default: false
  attr :current_user, :any, default: nil
  attr :can_edit_dashboard, :boolean, default: false
  attr :is_public_access, :boolean, default: false
  attr :public_token, :string, default: nil
  attr :kpi_values, :map, default: %{}
  attr :kpi_visuals, :map, default: %{}
  attr :timeseries, :map, default: %{}
  attr :category, :map, default: %{}
  attr :text_widgets, :map, default: %{}
  attr :export_params, :map, default: %{}
  attr :widget_export, :map, default: %{type: :dashboard}
  attr :print_width, :integer, default: nil

  def grid(assigns) do
    assigns =
      assigns
      |> assign_new(:grid_items, fn ->
        grid_items(assigns.dashboard)
      end)

    assigns = assign(assigns, :has_grid_items, assigns.grid_items != [])

    assigns =
      assigns
      |> assign_new(:text_items, fn -> text_items(assigns.grid_items) end)
      |> assign_new(:export_params, fn -> %{} end)
      |> assign_new(:widget_export, fn -> %{type: :dashboard} end)
      |> assign(:grid_dom_id, "dashboard-grid")
      |> assign_new(:print_width, fn -> nil end)

    assigns = assign(assigns, :print_container_style, build_print_container_style(assigns))

    ~H"""
    <div class={[
      "mb-6",
      if(@has_grid_items, do: nil, else: "hidden")
    ]}>
      <div
        id={@grid_dom_id}
        class="grid-stack opacity-0 pointer-events-none transition-opacity duration-300"
        style={@print_container_style}
        phx-update="ignore"
        phx-hook="DashboardGrid"
        data-print-mode={if @print_mode, do: "true", else: "false"}
        data-editable={
          if !@is_public_access && @current_user && @can_edit_dashboard,
            do: "true",
            else: "false"
        }
        data-cols="12"
        data-min-rows="8"
        data-add-btn-id={"dashboard-" <> @dashboard.id <> "-add-widget"}
        data-colors={ChartColors.json_palette()}
        data-initial-grid={Jason.encode!(@grid_items)}
        data-initial-text={Jason.encode!(@text_items)}
        data-dashboard-id={@dashboard.id}
        data-public-token={@public_token}
      >
        <%= for widget <- @grid_items do %>
          <.grid_item
            widget={widget}
            editable={!@is_public_access && @current_user && @can_edit_dashboard}
            kpi_values={@kpi_values}
            kpi_visuals={@kpi_visuals}
            timeseries={@timeseries}
            category={@category}
            text_widgets={@text_widgets}
            export_params={@export_params}
            print_mode={@print_mode}
            dashboard_id={Map.get(@dashboard, :id) || Map.get(@dashboard, "id")}
            dashboard={@dashboard}
            widget_export={@widget_export}
          />
        <% end %>
      </div>
    </div>

    <div class="hidden" aria-hidden="true">
      <%= for widget <- @grid_items do %>
        <% data = widget_dataset(assigns, widget) %>
        <div
          id={"widget-data-#{data.widget_id}"}
          data-widget-id={data.widget_id}
          data-widget-type={data.widget_type}
          data-kpi-values={data.kpi_values}
          data-kpi-visual={data.kpi_visual}
          data-timeseries={data.timeseries}
          data-category={data.category}
          data-text={data.text}
          data-grid-id={@grid_dom_id}
          phx-hook="DashboardWidgetData"
        >
        </div>
      <% end %>
    </div>
    """
  end

  defp render_widget_body(assigns) do
    case assigns.widget_type do
      "kpi" -> render_kpi_body(assigns)
      "timeseries" -> render_timeseries_body(assigns)
      "category" -> render_category_body(assigns)
      "text" -> render_text_body(assigns)
      _ -> render_placeholder_body(assigns)
    end
  end

  defp build_print_container_style(assigns) do
    width = Map.get(assigns, :print_width)

    cond do
      !assigns.print_mode -> nil
      not is_integer(width) or width <= 0 -> nil
      true -> "width: #{width}px; max-width: 100%; margin: 0 auto;"
    end
  end

  defp render_kpi_body(assigns) do
    kpi_value = assigns.kpi_value_dataset
    kpi_visual = assigns.kpi_visual_dataset

    subtype = value_for(kpi_value, :subtype) || "number"
    size = value_for(kpi_value, :size) || "m"
    size_class = kpi_size_class(size)
    has_visual = truthy?(value_for(kpi_value, :has_visual)) || truthy?(value_for(kpi_visual, :id))

    visual_type =
      (value_for(kpi_value, :visual_type) || value_for(kpi_visual, :type) || "sparkline")
      |> String.downcase()

    gap =
      if subtype == "goal" and has_visual and visual_type == "progress", do: "6px", else: "12px"

    meta = kpi_meta(kpi_value, kpi_visual, subtype, has_visual, visual_type)

    assigns =
      assigns
      |> assign(:kpi_value, kpi_value)
      |> assign(:kpi_visual, kpi_visual)
      |> assign(:kpi_subtype, subtype)
      |> assign(:kpi_size_class, size_class)
      |> assign(:kpi_has_visual, has_visual)
      |> assign(:kpi_visual_type, visual_type)
      |> assign(:kpi_gap, gap)
      |> assign(:kpi_meta, meta)

    ~H"""
    <div class="grid-widget-body flex-1 flex flex-col items-stretch">
      <div
        class="kpi-wrap w-full flex flex-col flex-1 grow"
        style={"min-height: 0; gap: #{@kpi_gap};"}
      >
        <div class="kpi-top">
          {render_kpi_top(assigns)}
        </div>
        <div class="kpi-meta" style={kpi_meta_style(@kpi_meta)}>
          <%= if @kpi_meta do %>
            {Phoenix.HTML.raw(@kpi_meta)}
          <% end %>
        </div>
        <div
          class={"kpi-visual " <> kpi_visual_class(@kpi_visual_type)}
          data-visual-type={@kpi_visual_type}
          data-echarts-ready="0"
          style={kpi_visual_style(@kpi_has_visual, @kpi_visual_type)}
        >
        </div>
      </div>
    </div>
    """
  end

  defp render_kpi_top(%{kpi_subtype: "split"} = assigns) do
    current = value_for(assigns.kpi_value, :current)
    previous = value_for(assigns.kpi_value, :previous)

    show_diff =
      truthy?(value_for(assigns.kpi_value, :show_diff)) and previous not in [nil, 0] and
        is_number(previous) and is_number(current)

    diff_badge =
      if show_diff do
        delta = current - previous
        pct = if previous != 0, do: delta / abs(previous) * 100, else: nil
        pct_text = format_percentage_value(pct)
        up = delta >= 0

        color_class =
          if up,
            do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200",
            else: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"

        arrow =
          if up do
            ~s(<span class="inline-block align-middle" style="width:0;height:0;border-left:4px solid transparent;border-right:4px solid transparent;border-bottom:6px solid currentColor;line-height:0"></span>)
          else
            ~s(<span class="inline-block align-middle" style="width:0;height:0;border-left:4px solid transparent;border-right:4px solid transparent;border-top:6px solid currentColor;line-height:0"></span>)
          end

        Phoenix.HTML.raw("""
        <span class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium leading-none whitespace-nowrap #{color_class}">
          #{arrow}
          <span class="sr-only"> #{if up, do: "Increased", else: "Decreased"} by </span>
          <span>#{pct_text}</span>
        </span>
        """)
      else
        nil
      end

    assigns =
      assigns
      |> assign(:current_label, format_number(value_for(assigns.kpi_value, :current)))
      |> assign(:previous_label, format_number(value_for(assigns.kpi_value, :previous)))
      |> assign(:diff_badge, diff_badge)

    ~H"""
    <div class="w-full">
      <div class="flex items-baseline justify-between w-full">
        <div class={[
          "flex flex-wrap items-baseline gap-x-2",
          @kpi_size_class,
          "font-bold text-gray-900 dark:text-white"
        ]}>
          <span>{@current_label}</span>
          <span class="text-sm font-medium text-gray-500 dark:text-slate-400">
            from {@previous_label}
          </span>
        </div>
        <%= if @diff_badge do %>
          {@diff_badge}
        <% end %>
      </div>
    </div>
    """
  end

  defp render_kpi_top(%{kpi_subtype: "goal"} = assigns) do
    value_label = format_number(value_for(assigns.kpi_value, :value))
    target_label = format_number(value_for(assigns.kpi_value, :target))
    show_progress = assigns.kpi_has_visual && assigns.kpi_visual_type == "progress"

    assigns =
      assigns
      |> assign(:value_label, value_label)
      |> assign(:target_label, if(target_label == "—", do: "", else: target_label))
      |> assign(:show_progress, show_progress)

    ~H"""
    <div class="w-full">
      <div class="flex items-baseline justify-between w-full">
        <div class={[
          "flex flex-wrap items-baseline gap-x-2",
          @kpi_size_class,
          "font-bold text-gray-900 dark:text-white"
        ]}>
          <span>{@value_label}</span>
        </div>
        <%= if @target_label != "" do %>
          <div class="flex flex-col items-end gap-1 text-right">
            <span class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium leading-none whitespace-nowrap bg-slate-100 text-slate-700 dark:bg-slate-800/70 dark:text-slate-200">
              Goal
            </span>
            <%= unless @show_progress do %>
              <span class="text-sm font-medium text-gray-500 dark:text-slate-400">
                {@target_label}
              </span>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_kpi_top(assigns) do
    value_label = format_number(value_for(assigns.kpi_value, :value))

    assigns =
      assigns
      |> assign(:value_label, value_label)

    ~H"""
    <div class={[@kpi_size_class, "font-bold text-gray-900 dark:text-white"]}>
      {@value_label}
    </div>
    """
  end

  defp kpi_meta(_kpi_value, _kpi_visual, subtype, _has_visual, _visual_type)
       when subtype != "goal",
       do: nil

  defp kpi_meta(kpi_value, kpi_visual, "goal", has_visual, visual_type) do
    ratio = value_for(kpi_value, :progress_ratio) || value_for(kpi_visual, :ratio)
    target_label = format_number(value_for(kpi_value, :target))
    invert_goal = truthy?(value_for(kpi_value, :invert))
    show_progress = has_visual && visual_type == "progress"

    if show_progress do
      pct_text = format_percent(ratio)

      status_class =
        cond do
          is_nil(ratio) -> "text-gray-700 dark:text-slate-200"
          invert_goal && ratio <= 1 -> "text-teal-600 dark:text-teal-300"
          invert_goal && ratio > 1 -> "text-red-600 dark:text-red-300"
          ratio >= 1 -> "text-green-600 dark:text-green-300"
          true -> "text-teal-600 dark:text-teal-300"
        end

      goal_markup =
        if target_label != "" and target_label != "—" do
          "<span class=\"text-sm font-medium text-gray-500 dark:text-slate-400\">#{target_label}</span>"
        else
          ""
        end

      """
      <span class="text-sm font-semibold #{status_class}">#{pct_text}</span>
      #{goal_markup}
      """
    else
      nil
    end
  end

  defp kpi_meta_style(nil), do: "display: none;"

  defp kpi_meta_style(_meta),
    do:
      "display: flex; align-items: baseline; justify-content: space-between; gap: 8px; margin-top: auto; margin-bottom: -8px;"

  defp kpi_visual_class("progress"), do: "kpi-progress"
  defp kpi_visual_class(_), do: "kpi-spark"

  defp kpi_visual_style(false, _type), do: "display: none;" <> sparkline_default_style()

  defp kpi_visual_style(true, "progress"),
    do:
      "margin-top: 4px; height: 20px; width: 100%; margin-left: 0; margin-right: 0; margin-bottom: 0;"

  defp kpi_visual_style(true, _), do: sparkline_default_style()

  defp sparkline_default_style,
    do:
      "margin-top: auto; height: 40px; width: calc(100% + 24px); margin-left: -12px; margin-right: -12px; margin-bottom: -12px;"

  defp kpi_size_class("s"), do: "text-2xl"
  defp kpi_size_class("l"), do: "text-4xl"
  defp kpi_size_class(_), do: "text-3xl"

  defp render_timeseries_body(assigns) do
    ~H"""
    <div class="grid-widget-body flex-1 flex">
      <div class="ts-chart w-full h-full" data-echarts-ready="0"></div>
    </div>
    """
  end

  defp render_category_body(assigns) do
    ~H"""
    <div class="grid-widget-body flex-1 flex">
      <div class="cat-chart w-full h-full" data-echarts-ready="0"></div>
    </div>
    """
  end

  defp render_text_body(assigns) do
    dataset = assigns.text_dataset || %{}
    subtype = value_for(dataset, :subtype) || "header"

    body_classes =
      [
        "grid-widget-body",
        "flex-1",
        "flex",
        "text-widget-body",
        "flex-col",
        "gap-2",
        "px-4",
        "pt-0",
        "pb-4"
      ]
      |> Enum.concat(assigns.text_alignment_classes)

    assigns =
      assigns
      |> assign(:text_subtype, subtype)
      |> assign(:text_body_classes, body_classes)
      |> assign(:text_title, value_for(dataset, :title) || "")
      |> assign(:text_title_size_class, text_title_size_class(value_for(dataset, :title_size)))
      |> assign(:text_subtitle, value_for(dataset, :subtitle) || "")
      |> assign(:text_html, value_for(dataset, :payload) || "")

    ~H"""
    <div
      class={@text_body_classes}
      data-text-subtype={@text_subtype}
      style={text_body_style(@text_subtype)}
    >
      <%= if @text_subtype == "html" do %>
        <div class="text-widget-html w-full leading-relaxed">
          {text_widget_html(@text_html)}
        </div>
      <% else %>
        <div class="text-widget-header-content w-full flex flex-col gap-2">
          <div class={["text-widget-title font-semibold leading-tight", @text_title_size_class]}>
            <%= if String.trim(@text_title) == "" do %>
              <span>&nbsp;</span>
            <% else %>
              {@text_title}
            <% end %>
          </div>
          <%= if String.trim(@text_subtitle) != "" do %>
            <div class="text-widget-subtitle text-base leading-relaxed opacity-80">
              {text_widget_subtitle(@text_subtitle)}
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_placeholder_body(assigns) do
    ~H"""
    <div class="grid-widget-body flex-1 flex items-center justify-center text-sm text-gray-500 dark:text-slate-400">
      Chart is coming soon
    </div>
    """
  end

  defp content_classnames(widget_type) do
    [
      "grid-stack-item-content",
      "bg-white",
      "dark:bg-slate-800",
      "border",
      "border-gray-200",
      "dark:border-slate-700",
      "rounded-md",
      "shadow",
      "p-3",
      "text-gray-700",
      "dark:text-slate-300",
      "flex",
      "flex-col",
      "group"
    ]
  end

  defp content_style("text", dataset) do
    color_id = value_for(dataset, :color_id) || "default"
    background = value_for(dataset, :background_color)
    text_color = value_for(dataset, :text_color)

    if background && String.downcase(color_id) != "default" do
      border_color =
        if background && color_dark?(background),
          do: "rgba(255,255,255,0.12)",
          else: "rgba(15,23,42,0.08)"

      "background-color: #{background}; color: #{text_color || ""}; border-color: #{border_color};"
    else
      nil
    end
  end

  defp content_style(_, _), do: nil

  defp header_classnames("text") do
    [
      "grid-widget-header",
      "flex",
      "items-center",
      "justify-between",
      "border-b",
      "border-transparent",
      "mb-0",
      "pb-0"
    ]
  end

  defp header_classnames(_widget_type) do
    [
      "grid-widget-header",
      "flex",
      "items-center",
      "justify-between",
      "mb-2",
      "pb-1",
      "border-b",
      "border-gray-100",
      "dark:border-slate-700/60"
    ]
  end

  defp header_style("text"), do: "min-height: 1.75rem;"
  defp header_style(_), do: nil

  defp title_classnames("text") do
    [
      "grid-widget-title",
      "font-semibold",
      "truncate",
      "text-gray-900",
      "dark:text-white",
      "opacity-0",
      "pointer-events-none"
    ]
  end

  defp title_classnames(_widget_type) do
    [
      "grid-widget-title",
      "font-semibold",
      "truncate",
      "text-gray-900",
      "dark:text-white"
    ]
  end

  defp title_attrs("text"), do: [role: "presentation"]
  defp title_attrs(_), do: []

  defp title_aria_hidden("text"), do: "true"
  defp title_aria_hidden(_), do: nil

  defp title_style("text"), do: "min-height: 1.25rem;"
  defp title_style(_), do: nil

  defp title_content("text", _title), do: Phoenix.HTML.raw("&nbsp;")
  defp title_content(_type, title), do: Phoenix.HTML.html_escape(title)

  defp widget_title_data("text", dataset, _title), do: value_for(dataset, :title) || ""
  defp widget_title_data(_, _dataset, title), do: title

  defp text_alignment_classes("text", dataset) do
    alignment =
      dataset
      |> value_for(:alignment)
      |> to_string()
      |> String.downcase()

    case alignment do
      "left" -> ["items-start", "justify-center", "text-left"]
      "right" -> ["items-end", "justify-center", "text-right"]
      _ -> ["items-center", "justify-center", "text-center"]
    end
  end

  defp text_alignment_classes(_, _), do: []

  defp text_body_style("html"),
    do: "justify-content: flex-start; align-items: stretch; text-align: left; overflow-y: auto;"

  defp text_body_style("header"), do: "justify-content: center;"
  defp text_body_style(_), do: nil

  defp text_title_size_class("small"), do: "text-2xl"
  defp text_title_size_class("medium"), do: "text-3xl"
  defp text_title_size_class("large"), do: "text-4xl"
  defp text_title_size_class(_), do: "text-4xl"

  defp text_widget_html(html) do
    html
    |> to_string()
    |> case do
      "" -> "<div class=\"text-xs opacity-60 italic\">No HTML content</div>"
      other -> other
    end
    |> Phoenix.HTML.raw()
  end

  defp text_widget_subtitle(subtitle) do
    subtitle
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace(~r/\r?\n/, "<br />")
    |> Phoenix.HTML.raw()
  end

  defp value_for(nil, _), do: nil

  defp value_for(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp value_for(_other, _key), do: nil

  defp truthy?(value), do: value in [true, "true", 1, "1"]

  defp format_number(nil), do: "—"
  defp format_number(%Decimal{} = decimal), do: decimal |> Decimal.to_float() |> format_number()

  defp format_number(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: "—", else: trimmed
  end

  defp format_number(value) when is_integer(value), do: format_number(value * 1.0)

  defp format_number(value) when is_float(value) do
    abs_value = abs(value)

    if abs_value >= 1000 do
      units = ["", "K", "M", "B", "T"]

      {scaled, idx} =
        Enum.reduce_while(0..(length(units) - 1), {abs_value, 0}, fn i, {num, _} ->
          cond do
            i == length(units) - 1 ->
              {:halt, {num, i}}

            num < 1000 ->
              {:halt, {num, i}}

            true ->
              {:cont, {num / 1000, i + 1}}
          end
        end)

      unit = Enum.at(units, idx)
      decimals = if scaled < 10, do: 2, else: 1
      prefix = if value < 0, do: "-", else: ""
      "#{prefix}#{trim_trailing_zero(float_to_string(scaled, decimals))}#{unit}"
    else
      trim_trailing_zero(float_to_string(value, 2))
    end
  end

  defp format_number(_other), do: "—"

  defp format_percent(nil), do: "—"

  defp format_percent(ratio) when is_number(ratio) do
    pct = ratio * 100
    decimals = if abs(pct) < 10, do: 1, else: 0
    "#{trim_trailing_zero(float_to_string(pct, decimals))}%"
  end

  defp format_percent(_), do: "—"

  defp format_percentage_value(nil), do: "—"

  defp format_percentage_value(pct) when is_number(pct) do
    decimals = if abs(pct) < 10, do: 2, else: 1
    "#{trim_trailing_zero(float_to_string(abs(pct), decimals))}%"
  end

  defp format_percentage_value(_), do: "—"

  defp float_to_string(value, decimals) do
    :erlang.float_to_binary(value * 1.0, decimals: decimals)
  end

  defp trim_trailing_zero(value) do
    value
    |> String.replace(~r/\.0+$/, "")
    |> String.replace(~r/(\.\d*?)0+$/, "\\1")
    |> String.trim_trailing(".")
  end

  defp color_dark?(color) when is_binary(color) do
    color
    |> String.trim()
    |> String.downcase()
    |> case do
      <<"#", rest::binary>> ->
        color_dark?(rest)

      <<r1::binary-size(1), r2::binary-size(1), g1::binary-size(1), g2::binary-size(1),
        b1::binary-size(1), b2::binary-size(1)>> = hex ->
        with {r, ""} <- Integer.parse(r1 <> r2, 16),
             {g, ""} <- Integer.parse(g1 <> g2, 16),
             {b, ""} <- Integer.parse(b1 <> b2, 16) do
          luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
          luminance < 0.5
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  defp color_dark?(_), do: false

  defp normalize_export_params(params) when is_map(params), do: params

  defp normalize_export_params(params) when is_binary(params) do
    URI.decode_query(params)
  rescue
    _ -> %{}
  end

  defp normalize_export_params(_), do: %{}

  defp normalize_widget_export(%{type: :monitor, monitor_id: id} = config) when is_binary(id) do
    Map.put(config, :type, :monitor)
  end

  defp normalize_widget_export(%{type: :dashboard} = config),
    do: Map.put(config, :type, :dashboard)

  defp normalize_widget_export(_), do: %{type: :dashboard}

  defp widget_export_links(%{type: :dashboard}, dashboard_id, widget_id, params)
       when is_binary(dashboard_id) do
    export_params = params || %{}

    links = %{
      pdf: ~p"/export/dashboards/#{dashboard_id}/widgets/#{widget_id}/pdf?#{export_params}",
      png_light:
        ~p"/export/dashboards/#{dashboard_id}/widgets/#{widget_id}/png?#{Map.put(export_params, "theme", "light")}",
      png_dark:
        ~p"/export/dashboards/#{dashboard_id}/widgets/#{widget_id}/png?#{Map.put(export_params, "theme", "dark")}"
    }

    {:ok, links}
  end

  defp widget_export_links(
         %{type: :monitor, monitor_id: monitor_id},
         _dashboard_id,
         widget_id,
         params
       )
       when is_binary(monitor_id) do
    export_params = params || %{}

    links = %{
      pdf: ~p"/export/monitors/#{monitor_id}/widgets/#{widget_id}/pdf?#{export_params}",
      png_light:
        ~p"/export/monitors/#{monitor_id}/widgets/#{widget_id}/png?#{Map.put(export_params, "theme", "light")}",
      png_dark:
        ~p"/export/monitors/#{monitor_id}/widgets/#{widget_id}/png?#{Map.put(export_params, "theme", "dark")}"
    }

    {:ok, links}
  end

  defp widget_export_links(_, _, _, _), do: :error

  attr :widget, :map, required: true
  attr :editable, :boolean, default: false
  attr :kpi_values, :map, default: %{}
  attr :kpi_visuals, :map, default: %{}
  attr :timeseries, :map, default: %{}
  attr :category, :map, default: %{}
  attr :text_widgets, :map, default: %{}
  attr :export_params, :map, default: %{}
  attr :print_mode, :boolean, default: false
  attr :dashboard_id, :string, default: nil
  attr :dashboard, :map, required: true
  attr :widget_export, :map, default: %{type: :dashboard}

  def grid_item(assigns) do
    widget_type = widget_type(assigns.widget)
    widget_id = widget_id(assigns.widget)
    kpi_value_dataset = fetch_dataset(assigns.kpi_values, widget_id)
    kpi_visual_dataset = fetch_dataset(assigns.kpi_visuals, widget_id)
    timeseries_dataset = fetch_dataset(assigns.timeseries, widget_id)
    category_dataset = fetch_dataset(assigns.category, widget_id)
    text_dataset = fetch_dataset(assigns.text_widgets, widget_id)

    assigns =
      assigns
      |> assign(:widget_id, widget_id)
      |> assign(:grid, grid_position(assigns.widget))
      |> assign(:title, widget_title(assigns.widget))
      |> assign(:widget_type, widget_type)
      |> assign(:kpi_value_dataset, kpi_value_dataset)
      |> assign(:kpi_visual_dataset, kpi_visual_dataset)
      |> assign(:timeseries_dataset, timeseries_dataset)
      |> assign(:category_dataset, category_dataset)
      |> assign(:text_dataset, text_dataset)
      |> assign(:content_classnames, content_classnames(widget_type))
      |> assign(:header_classnames, header_classnames(widget_type))
      |> assign(:title_classnames, title_classnames(widget_type))
      |> assign(:title_attrs, title_attrs(widget_type))
      |> assign(:text_alignment_classes, text_alignment_classes(widget_type, text_dataset))
      |> assign(:export_params, normalize_export_params(assigns.export_params || %{}))
      |> assign(:print_mode, Map.get(assigns, :print_mode, false))
      |> assign(:widget_export, normalize_widget_export(Map.get(assigns, :widget_export)))

    ~H"""
    <div
      class="grid-stack-item"
      gs-w={@grid.w}
      gs-h={@grid.h}
      gs-x={@grid.x}
      gs-y={@grid.y}
      gs-id={@widget_id}
    >
      <div
        class={@content_classnames}
        id={"grid-widget-content-#{@widget_id}"}
        data-widget-id={@widget_id}
        data-widget-type={@widget_type}
        data-text-widget={if @widget_type == "text", do: "1", else: nil}
        data-widget-title={widget_title_data(@widget_type, @text_dataset, @title)}
        style={content_style(@widget_type, @text_dataset)}
      >
        <div class={@header_classnames} style={header_style(@widget_type)}>
          <div class="grid-widget-handle cursor-move flex-1 flex items-center gap-2 py-1 min-w-0">
            <div
              class={@title_classnames}
              aria-hidden={title_aria_hidden(@widget_type)}
              style={title_style(@widget_type)}
              data-original-title={@title}
              {@title_attrs}
            >
              {title_content(@widget_type, @title)}
            </div>
          </div>
          <div class="grid-widget-actions flex items-center gap-1 opacity-0 transition-opacity duration-150 group-hover:opacity-100 group-focus-within:opacity-100">
            <%= unless @print_mode do %>
              <%= with {:ok, links} <-
                      widget_export_links(@widget_export, @dashboard_id, @widget_id, @export_params) do %>
                <div
                  id={"widget-download-menu-#{@widget_id}"}
                  class="relative"
                  data-widget-download-menu
                  data-widget-id={@widget_id}
                  data-default-label="Export"
                  data-open="false"
                  phx-hook="DownloadMenu"
                >
                  <button
                    type="button"
                    data-role="download-button"
                    class="inline-flex items-center p-1 rounded group"
                    aria-label="Export widget"
                    aria-haspopup="menu"
                    aria-expanded="false"
                    onclick="window.TrifleDownloads && window.TrifleDownloads.toggleWidgetMenu(this);"
                  >
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke-width="1.5"
                      stroke="currentColor"
                      class="h-4 w-4 text-teal-600 dark:text-teal-300 transition-colors group-hover:text-teal-700 dark:group-hover:text-teal-200"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
                      />
                    </svg>
                    <span class="sr-only" data-role="download-text">Export</span>
                  </button>

                  <div
                    data-role="download-dropdown"
                    data-widget-dropdown
                    class="absolute right-0 top-7 w-44 bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-md shadow-lg py-1 z-50 hidden"
                    role="menu"
                    aria-hidden="true"
                  >
                    <a
                      data-export-link
                      onclick="window.TrifleDownloads && window.TrifleDownloads.handleWidgetExportClick(this);"
                      href={links.pdf}
                      target="download_iframe"
                      class="flex items-center px-3 py-2 text-xs text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-700"
                      title="Export PDF"
                      role="menuitem"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        class="h-4 w-4 mr-2 text-rose-600 dark:text-rose-300"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
                        />
                      </svg>
                      PDF (print)
                    </a>

                    <a
                      data-export-link
                      onclick="window.TrifleDownloads && window.TrifleDownloads.handleWidgetExportClick(this);"
                      href={links.png_light}
                      target="download_iframe"
                      class="flex items-center px-3 py-2 text-xs text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-700"
                      title="Export PNG (light)"
                      role="menuitem"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        class="h-4 w-4 mr-2 text-amber-600 dark:text-amber-400"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
                        />
                      </svg>
                      PNG (light)
                    </a>

                    <a
                      data-export-link
                      onclick="window.TrifleDownloads && window.TrifleDownloads.handleWidgetExportClick(this);"
                      href={links.png_dark}
                      target="download_iframe"
                      class="flex items-center px-3 py-2 text-xs text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-700"
                      title="Export PNG (dark)"
                      role="menuitem"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        class="h-4 w-4 mr-2 text-amber-600 dark:text-amber-400"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
                        />
                      </svg>
                      PNG (dark)
                    </a>
                  </div>
                </div>
              <% end %>
            <% end %>
            <button
              type="button"
              class="grid-widget-expand inline-flex items-center p-1 rounded group"
              data-widget-id={@widget_id}
              title="Expand widget"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="h-4 w-4 text-gray-600 dark:text-slate-300 transition-colors group-hover:text-gray-800 dark:group-hover:text-slate-100"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 9M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 9m5.25 11.25h-4.5m4.5 0v-4.5m0 4.5L15 15"
                />
              </svg>
            </button>
            <%= if @editable do %>
              <button
                type="button"
                class="grid-widget-edit inline-flex items-center p-1 rounded group"
                data-widget-id={@widget_id}
                title="Edit widget"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="h-4 w-4 text-gray-600 dark:text-slate-300 transition-colors group-hover:text-gray-800 dark:group-hover:text-slate-100"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z"
                  />
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                  />
                </svg>
              </button>
            <% end %>
          </div>
        </div>
        {render_widget_body(assigns)}
      </div>
    </div>
    """
  end

  defp widget_dataset(assigns, widget) do
    widget_id = widget_id(widget)
    widget_type = widget_type(widget)

    base = %{
      widget_id: widget_id,
      widget_type: widget_type,
      kpi_values: nil,
      kpi_visual: nil,
      timeseries: nil,
      category: nil,
      text: nil
    }

    case widget_type do
      "kpi" ->
        base
        |> Map.put(:kpi_values, encode_dataset(fetch_dataset(assigns.kpi_values, widget_id)))
        |> Map.put(:kpi_visual, encode_dataset(fetch_dataset(assigns.kpi_visuals, widget_id)))

      "timeseries" ->
        Map.put(base, :timeseries, encode_dataset(fetch_dataset(assigns.timeseries, widget_id)))

      "category" ->
        Map.put(base, :category, encode_dataset(fetch_dataset(assigns.category, widget_id)))

      "text" ->
        Map.put(base, :text, encode_dataset(fetch_dataset(assigns.text_widgets, widget_id)))

      _ ->
        base
    end
  end

  defp fetch_dataset(map, id) when is_map(map) do
    map
    |> Map.get(id)
    |> case do
      nil -> Map.get(map, to_string(id))
      value -> value
    end
  end

  defp fetch_dataset(_map, _id), do: nil

  defp encode_dataset(nil), do: nil
  defp encode_dataset(data), do: Jason.encode!(data)

  defp widget_type(widget) do
    widget
    |> Map.get("type", "kpi")
    |> to_string()
    |> String.downcase()
  end

  defp widget_id(widget) do
    widget
    |> Map.get("id") || widget |> Map.get(:id) || widget |> Map.get("uuid") ||
      widget
      |> Map.get(:uuid)
      |> to_string()
  end

  defp grid_position(widget) do
    %{
      w: widget |> Map.get("w") || widget |> Map.get(:w) || 3,
      h: widget |> Map.get("h") || widget |> Map.get(:h) || 2,
      x: widget |> Map.get("x") || widget |> Map.get(:x) || 0,
      y: widget |> Map.get("y") || widget |> Map.get(:y) || 0
    }
    |> Enum.into(%{}, fn {k, value} -> {k, to_string(value)} end)
  end

  defp widget_title(widget) do
    widget["title"] || widget[:title] || default_title(widget)
  end

  defp default_title(widget) do
    widget_id = widget_id(widget)
    prefix = "Widget "

    suffix =
      widget_id
      |> String.slice(0, 6)
      |> case do
        nil -> "—"
        slice -> slice
      end

    prefix <> suffix
  end

  def grid_items(dashboard) do
    dashboard
    |> Map.get(:payload, %{})
    |> Map.get("grid", [])
    |> normalize_items()
  end

  def text_items(grid_items), do: TextWidgets.widgets(grid_items)

  defp normalize_items(items) when is_list(items), do: items
  defp normalize_items(_other), do: []
end
