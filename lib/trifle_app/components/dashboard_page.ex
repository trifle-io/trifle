defmodule TrifleApp.Components.DashboardPage do
  @moduledoc """
  Shared dashboard surface extracted from DashboardLive for reuse across contexts.
  """
  use TrifleApp, :html

  import TrifleApp.Components.DashboardFooter, only: [dashboard_footer: 1]
  import TrifleApp.Components.GranularitySelect, only: [granularity_select: 1]
  import TrifleApp.Components.TimeframeInput, only: [timeframe_input: 1]

  import TrifleApp.DashboardLive,
    only: [
      dashboard_has_key?: 1,
      build_url_params: 1,
      get_summary_stats: 1
    ]

  alias Trifle.Stats.Source
  alias TrifleApp.Components.DataTable
  alias TrifleApp.Components.DashboardWidgets.WidgetEditor
  alias TrifleApp.Components.DashboardWidgets.WidgetView
  alias TrifleApp.DesignSystem.ChartColors
  alias TrifleApp.Granularity

  def dashboard(assigns) do
    ~H"""
    <div
      id="dashboard-page-root"
      class="flex flex-col dark:bg-slate-900 min-h-screen relative"
      phx-hook="FileDownload"
    >
      <%= if @print_mode do %>
        <style>
          @media print {
            @page { size: A3; margin: 8mm; }
            /* Force white page background and avoid printing element backgrounds */
            html, body { background: #ffffff !important; -webkit-print-color-adjust: economy !important; print-color-adjust: economy !important; }
            .dark, .dark body { background: #ffffff !important; }
            /* Remove any focus rings, outlines, and shadows that can appear thicker in print */
            *, *::before, *::after { box-shadow: none !important; text-shadow: none !important; outline: none !important; }
            /* Common content containers */
            .grid-stack-item-content { box-shadow: none !important; }
            .container { max-width: 100% !important; width: 100% !important; }
            .grid-stack { max-width: 100% !important; width: 100% !important; }
            #phx-topbar { display: none !important; }
          }
        </style>
      <% end %>
      <!-- Hidden iframe target for downloads to avoid navigating away from LiveView -->
      <iframe
        name="download_iframe"
        style="display:none"
        aria-hidden="true"
        onload="window.__resetDownloadMenus && window.__resetDownloadMenus(); window.dispatchEvent(new CustomEvent('download:complete'))"
      >
      </iframe>
      <script>
        window.__resetDownloadMenus = window.__resetDownloadMenus || function(){
          try {
            var menus = document.querySelectorAll('[data-download-menu],[data-widget-download-menu]');
            menus.forEach(function(menu){
              var button = menu.querySelector('[data-role=download-button]');
              var label = menu.querySelector('[data-role=download-text]');
              var icon = menu.querySelector('[data-role=download-icon]');
              var spinner = menu.querySelector('[data-role=download-spinner]');
              var defaultLabel = (menu.dataset && menu.dataset.defaultLabel) || 'Download';
              if (button) {
                button.disabled = false;
                button.classList.remove('opacity-70','cursor-wait');
                button.removeAttribute('aria-busy');
                button.removeAttribute('data-loading');
              }
              if (icon) icon.classList.remove('hidden');
              if (spinner) spinner.classList.add('hidden');
              if (label && defaultLabel) {
                label.textContent = defaultLabel;
              }
            });
          } catch (_) {}
        };
        window.__downloadPoller = window.__downloadPoller || setInterval(function(){
          try {
            var m = document.cookie.match(/(?:^|; )download_token=([^;]+)/);
            if (m) {
              // Clear cookie and reset UI
              document.cookie = 'download_token=; Max-Age=0; path=/';
              if (window.__resetDownloadMenus) window.__resetDownloadMenus();
              window.dispatchEvent(new CustomEvent('download:complete'));
            }
          } catch (e) {}
        }, 500);
      </script>
      <!-- Loading Overlay (covers entire page; message at 1/3 height) -->
      <%= if (@loading_chunks && @loading_progress) || @transponding do %>
        <div class="absolute inset-0 bg-white bg-opacity-75 dark:bg-slate-900 dark:bg-opacity-90 z-50">
          <div class="absolute left-1/2 -translate-x-1/2" style="top: 33%;">
            <div class="flex flex-col items-center space-y-3">
              <div class="flex items-center space-x-2">
                <div class="animate-spin rounded-full h-6 w-6 border-2 border-gray-300 dark:border-slate-600 border-t-teal-500">
                </div>
                <span class="text-sm text-gray-600 dark:text-white">
                  <%= if @transponding do %>
                    Transponding data...
                  <% else %>
                    Scientificating piece {@loading_progress.current} of {@loading_progress.total}...
                  <% end %>
                </span>
              </div>
              <!-- Always reserve space for progress bar to keep text position consistent -->
              <div class="w-64 h-2">
                <%= if @loading_chunks && @loading_progress do %>
                  <div class="w-full bg-gray-200 dark:bg-slate-600 rounded-full h-2">
                    <div
                      class="bg-teal-500 h-2 rounded-full transition-all duration-300"
                      style={"width: #{(@loading_progress.current / @loading_progress.total * 100)}%"}
                    >
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      <% end %>
      <main class="flex-1 w-full">
        <!-- Header -->
        <div class={if(@is_public_access, do: "mb-2", else: "mb-6")}>
          <div class="flex items-center justify-between">
            <!-- Left: Title only -->
            <div class="min-w-0">
              <h1 class="text-2xl font-bold text-gray-900 dark:text-white truncate">
                {@dashboard.name}
              </h1>
            </div>

            <%= if !@print_mode && !@is_public_access && @current_user && @can_edit_dashboard do %>
              <!-- Dashboard owner controls -->
              <div class="flex items-center justify-end gap-3 md:gap-4 flex-nowrap w-auto">
                <% add_btn_id = "dashboard-" <> @dashboard.id <> "-add-widget" %>
                <!-- Add Widget Button -->
                <button
                  id={add_btn_id}
                  type="button"
                  class="inline-flex items-center whitespace-nowrap rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
                  title="Add widget"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    viewBox="0 0 24 24"
                    fill="currentColor"
                    class="-ml-0.5 md:mr-1.5 h-4 w-4"
                  >
                    <path
                      fill-rule="evenodd"
                      d="M12 3.75a.75.75 0 01.75.75v6.75h6.75a.75.75 0 010 1.5H12.75v6.75a.75.75 0 01-1.5 0V12.75H4.5a.75.75 0 010-1.5h6.75V4.5a.75.75 0 01.75-.75z"
                      clip-rule="evenodd"
                    />
                  </svg>
                  <span class="hidden md:inline">Add Widget</span>
                </button>
                <.link
                  patch={~p"/dashboards/#{@dashboard.id}/configure"}
                  class="inline-flex items-center whitespace-nowrap rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                >
                  <svg
                    class="md:-ml-0.5 md:mr-1.5 h-4 w-4"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
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
                  <span class="hidden md:inline">Configure</span>
                </.link>
                
    <!-- Status Icon Badges -->
                <div id="status-badges" class="flex items-center gap-2" phx-hook="FastTooltip">
                  <!-- Public link -->
                  <%= if @dashboard.access_token do %>
                    <!-- Hidden element with the URL to copy -->
                    <span id="dashboard-public-url" class="hidden">
                      {url(@socket, ~p"/d/#{@dashboard.id}?token=#{@dashboard.access_token}")}
                    </span>
                    
    <!-- Has token: white/plain button with visual feedback - hidden on XS screens -->
                    <button
                      type="button"
                      phx-click={
                        JS.dispatch("phx:copy", to: "#dashboard-public-url")
                        |> JS.hide(to: "#header-link-icon")
                        |> JS.show(to: "#header-check-icon")
                        |> JS.hide(to: "#header-check-icon", transition: {"", "", ""}, time: 2000)
                        |> JS.show(to: "#header-link-icon", transition: {"", "", ""}, time: 2000)
                      }
                      class="cursor-pointer hidden sm:inline-flex items-center rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-xs font-medium text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                      data-tooltip="Copy public dashboard link"
                    >
                      <!-- Link Icon (default) -->
                      <svg
                        id="header-link-icon"
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
                          d="M8.288 15.038a5.25 5.25 0 0 1 7.424 0M5.106 11.856c3.807-3.808 9.98-3.808 13.788 0M1.924 8.674c5.565-5.565 14.587-5.565 20.152 0M12.53 18.22l-.53.53-.53-.53a.75.75 0 0 1 1.06 0Z"
                        />
                      </svg>
                      
    <!-- Check Icon (shown temporarily when copied) -->
                      <svg
                        id="header-check-icon"
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        class="h-5 w-5 text-green-600 hidden"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                        />
                      </svg>
                    </button>
                  <% else %>
                    <!-- No token: icon-only (no wrapper), hidden on XS -->
                    <div
                      class="hidden sm:inline-flex items-center justify-center rounded-md px-3 py-2"
                      data-tooltip="No public link available"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        class="h-5 w-5 text-gray-400 dark:text-slate-500"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M8.288 15.038a5.25 5.25 0 0 1 7.424 0M5.106 11.856c3.807-3.808 9.98-3.808 13.788 0M1.924 8.674c5.565-5.565 14.587-5.565 20.152 0M12.53 18.22l-.53.53-.53-.53a.75.75 0 0 1 1.06 0Z"
                        />
                      </svg>
                    </div>
                  <% end %>
                  
    <!-- Visibility badge -->
                  <%= if @dashboard.visibility do %>
                    <div
                      class="hidden sm:inline-flex items-center justify-center rounded-md px-3 py-2"
                      data-tooltip="Visible to everyone in organization"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        class="h-5 w-5 text-teal-600 dark:text-teal-400"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z"
                        />
                      </svg>
                    </div>
                  <% else %>
                    <div
                      class="hidden sm:inline-flex items-center justify-center rounded-md px-3 py-2"
                      data-tooltip="Private - only you can see this"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        class="h-5 w-5 text-gray-400 dark:text-slate-500"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z"
                        />
                      </svg>
                    </div>
                  <% end %>

                  <%= if @dashboard.locked do %>
                    <div
                      class="hidden sm:inline-flex items-center justify-center rounded-md px-3 py-2"
                      data-tooltip="Locked. Only the owner or organization admins can edit."
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        class="h-5 w-5 text-amber-500 dark:text-amber-400"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M16.5 10.5V7.5a4.5 4.5 0 0 0-9 0v3M6 10.5h12a1.5 1.5 0 0 1 1.5 1.5v6A1.5 1.5 0 0 1 18 19.5H6A1.5 1.5 0 0 1 4.5 18v-6A1.5 1.5 0 0 1 6 10.5Z"
                        />
                      </svg>
                      <span class="sr-only">Dashboard locked</span>
                    </div>
                  <% end %>
                </div>
              </div>
            <% else %>
              <!-- Non-owner or public access view -->
              <%= if !@is_public_access do %>
                <div class="flex items-center gap-2 w-64 justify-end">
                  <span class={[
                    "inline-flex items-center rounded-md px-2 py-1 text-xs font-medium",
                    if(@dashboard.visibility,
                      do:
                        "bg-blue-50 dark:bg-blue-900 text-blue-700 dark:text-blue-200 ring-1 ring-inset ring-blue-600/20 dark:ring-blue-500/30",
                      else:
                        "bg-gray-50 dark:bg-gray-900 text-gray-700 dark:text-gray-200 ring-1 ring-inset ring-gray-600/20 dark:ring-gray-500/30"
                    )
                  ]}>
                    {Trifle.Organizations.Dashboard.visibility_display(@dashboard.visibility)}
                  </span>
                  <%= if @dashboard.locked do %>
                    <span class="inline-flex items-center rounded-md px-2 py-1 text-xs font-medium bg-amber-50 dark:bg-amber-900 text-amber-700 dark:text-amber-300 ring-1 ring-inset ring-amber-500/30">
                      Locked
                    </span>
                  <% end %>
                </div>
              <% else %>
                <div class="w-64"></div>
              <% end %>
            <% end %>
          </div>
        </div>
        
    <!-- Filter Bar (only show if dashboard has a key) -->
        <%= if dashboard_has_key?(assigns) do %>
          <.live_component
            module={TrifleApp.Components.FilterBar}
            id="dashboard_filter_bar"
            config={@database_config}
            from={@from}
            to={@to}
            granularity={@granularity}
            smart_timeframe_input={@smart_timeframe_input}
            use_fixed_display={@use_fixed_display}
            available_granularities={@available_granularities}
            show_controls={!@print_mode}
            show_timeframe_dropdown={false}
            show_granularity_dropdown={false}
            sources={@sources || []}
            selected_source={@selected_source_ref}
            source_locked={true}
            force_granularity_dropdown={@print_mode}
          />
        <% end %>
        <% segment_definitions = @dashboard_segments || [] %>
        <%= if !@print_mode and segment_definitions != [] do %>
          <form
            id="dashboard-segments-form"
            class="mb-6 flex justify-center"
            phx-change="update_segment_filters"
            phx-submit="update_segment_filters"
          >
            <div class="flex flex-wrap items-center justify-center gap-4">
              <%= for segment <- segment_definitions do %>
                <% segment_name = segment["name"] %>
                <% label = segment["label"] || segment_name || "Segment" %>
                <% current_value = Map.get(@segment_values || %{}, segment_name, "") %>
                <label class="flex items-center gap-2 text-sm font-medium text-gray-700 dark:text-slate-300">
                  <span>{label}:</span>
                  <%= if segment["type"] == "text" do %>
                    <input
                      type="text"
                      name={"segments[#{segment_name}]"}
                      value={current_value}
                      placeholder={segment["placeholder"] || ""}
                      phx-debounce="500"
                      class="w-56 rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                    />
                  <% else %>
                    <% groups = segment["groups"] || [] %>
                    <% has_items = Enum.any?(groups, fn group -> (group["items"] || []) != [] end) %>
                    <div class="grid grid-cols-1">
                      <select
                        name={"segments[#{segment_name}]"}
                        class="col-start-1 row-start-1 w-56 appearance-none rounded-md border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-800 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm py-1.5 pr-8 pl-3"
                      >
                        <%= for group <- groups do %>
                          <% group_label = group["label"] %>
                          <%= if group_label && group_label != "" do %>
                            <optgroup label={group_label}>
                              <%= for item <- group["items"] || [] do %>
                                <% option_value = item["value"] || "" %>
                                <option value={option_value} selected={option_value == current_value}>
                                  {item["label"] || option_value}
                                </option>
                              <% end %>
                            </optgroup>
                          <% else %>
                            <%= for item <- group["items"] || [] do %>
                              <% option_value = item["value"] || "" %>
                              <option value={option_value} selected={option_value == current_value}>
                                {item["label"] || option_value}
                              </option>
                            <% end %>
                          <% end %>
                        <% end %>
                        <%= if !has_items do %>
                          <option value="" selected={current_value in [nil, ""]} disabled>
                            No options configured
                          </option>
                        <% end %>
                      </select>
                      <svg
                        viewBox="0 0 16 16"
                        fill="currentColor"
                        aria-hidden="true"
                        class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 dark:text-slate-400 sm:h-4 sm:w-4"
                      >
                        <path
                          d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z"
                          clip-rule="evenodd"
                          fill-rule="evenodd"
                        />
                      </svg>
                    </div>
                  <% end %>
                </label>
              <% end %>
            </div>
          </form>
        <% end %>
        <% export_params =
          build_url_params(%{
            granularity: @granularity,
            smart_timeframe_input: @smart_timeframe_input,
            use_fixed_display: @use_fixed_display,
            from: @from,
            to: @to,
            segment_values: @segment_values
          })
          |> then(fn params ->
            cond do
              is_binary(@resolved_key) and @resolved_key != "" ->
                Map.put(params, "key", @resolved_key)

              true ->
                params
            end
          end) %>

        <% grid_items = WidgetView.grid_items(@dashboard) %>
        <% has_grid_items = grid_items != [] %>
        <% text_items = WidgetView.text_items(grid_items) %>

        <WidgetView.grid
          dashboard={@dashboard}
          stats={@stats}
          print_mode={@print_mode}
          current_user={@current_user}
          can_edit_dashboard={@can_edit_dashboard}
          is_public_access={@is_public_access}
          public_token={@public_token}
          grid_items={grid_items}
          text_items={text_items}
          kpi_values={@widget_kpi_values || %{}}
          kpi_visuals={@widget_kpi_visuals || %{}}
          timeseries={@widget_timeseries || %{}}
          category={@widget_category || %{}}
          table={@widget_table || %{}}
          text_widgets={@widget_text || %{}}
          list={@widget_list || %{}}
          transponder_info={@transponder_info || %{}}
          export_params={export_params}
        />
        
    <!-- Configure Modal -->
        <%= if !@is_public_access && @live_action == :configure do %>
          <% configure_cancel = JS.patch(~p"/dashboards/#{@dashboard.id}") %>
          <.app_modal id="configure-modal" show={true} on_cancel={configure_cancel}>
            <:title>Configure Dashboard</:title>
            <:body>
              <div class="space-y-6">
                <.form
                  for={%{}}
                  id="dashboard-configure-form"
                  phx-change="segments_editor_change"
                  phx-submit="save_settings"
                  class="space-y-6"
                >
                  <!-- Dashboard Name -->
                  <div>
                    <label
                      for="configure_name"
                      class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2"
                    >
                      Dashboard Name
                    </label>
                    <input
                      type="text"
                      id="configure_name"
                      name="name"
                      value={@temp_name || @dashboard.name}
                      phx-keyup="update_temp_name"
                      class="w-full block rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                      placeholder="Dashboard name"
                    />
                  </div>
                  
    <!-- Source (editable) -->
                  <div>
                    <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
                      Source
                    </label>
                    <% grouped_sources = group_sources_for_select(@sources || []) %>
                    <div class="grid grid-cols-1 sm:max-w-xs">
                      <select
                        name="source_ref"
                        class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
                        disabled={grouped_sources == []}
                      >
                        <%= for {group_label, sources} <- grouped_sources do %>
                          <optgroup label={group_label}>
                            <%= for source <- sources do %>
                              <% value = source_option_value(source) %>
                              <option
                                value={value}
                                selected={source_selected?(@selected_source_ref, source)}
                              >
                                {Source.display_name(source)}
                              </option>
                            <% end %>
                          </optgroup>
                        <% end %>
                      </select>
                      <svg
                        viewBox="0 0 16 16"
                        fill="currentColor"
                        data-slot="icon"
                        aria-hidden="true"
                        class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 dark:text-slate-400 sm:h-4 sm:w-4"
                      >
                        <path
                          d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z"
                          clip-rule="evenodd"
                          fill-rule="evenodd"
                        />
                      </svg>
                    </div>
                    <%= if grouped_sources == [] do %>
                      <p class="mt-2 text-xs text-red-600 dark:text-red-400">
                        No available sources. Create a database or project first.
                      </p>
                    <% end %>
                  </div>
                  
    <!-- Dashboard Key -->
                  <div>
                    <label
                      for="configure_key"
                      class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2"
                    >
                      Key
                    </label>
                    <input
                      type="text"
                      id="configure_key"
                      name="key"
                      value={@dashboard.key || ""}
                      class="w-full block rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                      placeholder="e.g., sales.metrics"
                      required
                    />
                    <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                      Use regex capture groups to mark dynamic segments, for example <code>commodity::events::detail::(?&lt;source&gt;.*)</code>. The capture name should match the
                      segment name; otherwise segments fallback to positional order.
                    </p>
                  </div>

                  <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
                    <div class="mb-4">
                      <h3 class="text-sm font-semibold text-gray-900 dark:text-white">
                        Key Segments
                      </h3>
                      <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                        Configure dynamic parts of the dashboard key. Each segment becomes a filter exposed at the top of the dashboard.
                      </p>
                    </div>
                    <% configure_segments = @configure_segments || [] %>
                    <div class="space-y-6">
                      <%= for segment <- configure_segments do %>
                        <% segment_id = segment["id"] %>
                        <% segment_name = segment["name"] || "" %>
                        <% segment_label = segment["label"] || "" %>
                        <% segment_type = segment["type"] || "select" %>
                        <% placeholder = segment["placeholder"] || "" %>
                        <% default_value = segment["default_value"] || "" %>
                        <div class="rounded-lg border border-gray-200 dark:border-slate-700 bg-gray-50 dark:bg-slate-900/40 p-4 space-y-4">
                          <div class="flex flex-col md:flex-row md:items-start md:justify-between gap-4">
                            <div class="grid grid-cols-1 md:grid-cols-3 gap-4 w-full">
                              <div>
                                <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                                  Name
                                </label>
                                <input
                                  type="text"
                                  required
                                  name={"segments[#{segment_id}][name]"}
                                  value={segment_name}
                                  class="block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                                  placeholder="source"
                                />
                                <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                                  Matching placeholder name used in the key (e.g. (source)).
                                </p>
                              </div>
                              <div>
                                <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                                  Label
                                </label>
                                <input
                                  type="text"
                                  name={"segments[#{segment_id}][label]"}
                                  value={segment_label}
                                  class="block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                                  placeholder="Source"
                                />
                                <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                                  Display name shown above the dashboard.
                                </p>
                              </div>
                              <div>
                                <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                                  Segment Type
                                </label>
                                <div class="grid grid-cols-1">
                                  <select
                                    name={"segments[#{segment_id}][type]"}
                                    class="col-start-1 row-start-1 block w-full appearance-none rounded-md border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-800 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm py-1.5 pr-8 pl-3"
                                  >
                                    <option value="select" selected={segment_type != "text"}>
                                      Dropdown
                                    </option>
                                    <option value="text" selected={segment_type == "text"}>
                                      Text input
                                    </option>
                                  </select>
                                  <svg
                                    viewBox="0 0 16 16"
                                    fill="currentColor"
                                    aria-hidden="true"
                                    class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 dark:text-slate-400 sm:h-4 sm:w-4"
                                  >
                                    <path
                                      d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z"
                                      clip-rule="evenodd"
                                      fill-rule="evenodd"
                                    />
                                  </svg>
                                </div>
                              </div>
                            </div>
                            <button
                              type="button"
                              phx-click="segments_remove"
                              phx-value-id={segment_id}
                              class="inline-flex items-center gap-1 rounded-md bg-transparent px-3 py-2 text-xs font-medium text-red-600 hover:bg-red-500/10 dark:text-red-400"
                            >
                              <svg
                                xmlns="http://www.w3.org/2000/svg"
                                viewBox="0 0 20 20"
                                fill="currentColor"
                                class="h-4 w-4"
                              >
                                <path
                                  fill-rule="evenodd"
                                  d="M6.28 5.22a.75.75 0 0 1 1.06 0L10 7.94l2.66-2.72a.75.75 0 0 1 1.08 1.04L11.06 9l2.72 2.66a.75.75 0 1 1-1.04 1.08L10 10.06l-2.66 2.72a.75.75 0 1 1-1.08-1.04L8.94 9l-2.72-2.66a.75.75 0 0 1 0-1.06Z"
                                  clip-rule="evenodd"
                                />
                              </svg>
                              Remove
                            </button>
                          </div>

                          <%= if segment_type == "text" do %>
                            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                              <div>
                                <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                                  Placeholder
                                </label>
                                <input
                                  type="text"
                                  name={"segments[#{segment_id}][placeholder]"}
                                  value={placeholder}
                                  class="block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                                  placeholder="e.g., Enter product ID"
                                />
                              </div>
                              <div>
                                <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                                  Default value
                                </label>
                                <input
                                  type="text"
                                  name={"segments[#{segment_id}][default_value]"}
                                  value={default_value}
                                  class="block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                                  placeholder="Leave blank for no default"
                                />
                              </div>
                            </div>
                          <% else %>
                            <% groups = segment["groups"] || [] %>
                            <div class="space-y-4">
                              <%= for group <- groups do %>
                                <% group_id = group["id"] %>
                                <% group_label = group["label"] || "" %>
                                <% items = group["items"] || [] %>
                                <div class="rounded-md border border-gray-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-4 space-y-3">
                                  <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
                                    <div class="w-full">
                                      <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                                        Group label
                                      </label>
                                      <input
                                        type="text"
                                        name={"segments[#{segment_id}][groups][#{group_id}][label]"}
                                        value={group_label}
                                        class="block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                                        placeholder="Optional label"
                                      />
                                    </div>
                                    <button
                                      type="button"
                                      phx-click="segments_remove_group"
                                      phx-value-segment-id={segment_id}
                                      phx-value-group-id={group_id}
                                      class="inline-flex items-center gap-1 rounded-md bg-transparent px-3 py-2 text-xs font-medium text-red-600 hover:bg-red-500/10 dark:text-red-400"
                                    >
                                      <svg
                                        xmlns="http://www.w3.org/2000/svg"
                                        viewBox="0 0 20 20"
                                        fill="currentColor"
                                        class="h-4 w-4"
                                      >
                                        <path
                                          fill-rule="evenodd"
                                          d="M6.28 5.22a.75.75 0 0 1 1.06 0L10 7.94l2.66-2.72a.75.75 0 0 1 1.08 1.04L11.06 9l2.72 2.66a.75.75 0 1 1-1.04 1.08L10 10.06l-2.66 2.72a.75.75 0 1 1-1.08-1.04L8.94 9l-2.72-2.66a.75.75 0 0 1 0-1.06Z"
                                          clip-rule="evenodd"
                                        />
                                      </svg>
                                      Remove group
                                    </button>
                                  </div>
                                  <div class="space-y-3">
                                    <%= for item <- items do %>
                                      <% item_id = item["id"] %>
                                      <% item_label = item["label"] || "" %>
                                      <% item_value = item["value"] || "" %>
                                      <div class="grid grid-cols-1 md:grid-cols-[auto,1fr,1fr,auto] gap-3 md:items-center">
                                        <div class="flex items-center gap-2">
                                          <input
                                            type="radio"
                                            name={"segments[#{segment_id}][default_value]"}
                                            value={item_value}
                                            checked={item_value == default_value}
                                            class="h-4 w-4 text-teal-600 focus:ring-teal-500"
                                          />
                                          <span class="text-xs text-gray-500 dark:text-slate-400">
                                            Default
                                          </span>
                                        </div>
                                        <div>
                                          <label class="sr-only">Option label</label>
                                          <input
                                            type="text"
                                            name={"segments[#{segment_id}][groups][#{group_id}][items][#{item_id}][label]"}
                                            value={item_label}
                                            class="block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                                            placeholder="Label"
                                          />
                                        </div>
                                        <div>
                                          <label class="sr-only">Option value</label>
                                          <input
                                            type="text"
                                            name={"segments[#{segment_id}][groups][#{group_id}][items][#{item_id}][value]"}
                                            value={item_value}
                                            class="block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                                            placeholder="Value"
                                          />
                                        </div>
                                        <button
                                          type="button"
                                          phx-click="segments_remove_item"
                                          phx-value-segment-id={segment_id}
                                          phx-value-group-id={group_id}
                                          phx-value-item-id={item_id}
                                          class="inline-flex items-center justify-center rounded-md bg-transparent px-2 py-2 text-xs font-medium text-red-600 hover:bg-red-500/10 dark:text-red-400"
                                          aria-label="Remove option"
                                        >
                                          &times;
                                        </button>
                                      </div>
                                    <% end %>
                                  </div>
                                  <button
                                    type="button"
                                    phx-click="segments_add_item"
                                    phx-value-segment-id={segment_id}
                                    phx-value-group-id={group_id}
                                    class="inline-flex items-center gap-1 rounded-md bg-teal-600 px-3 py-2 text-xs font-semibold text-white shadow-sm hover:bg-teal-500"
                                  >
                                    <span aria-hidden="true">+</span> Add option
                                  </button>
                                </div>
                              <% end %>
                              <button
                                type="button"
                                phx-click="segments_add_group"
                                phx-value-segment-id={segment_id}
                                class="inline-flex items-center gap-1 rounded-md bg-teal-600 px-3 py-2 text-xs font-semibold text-white shadow-sm hover:bg-teal-500"
                              >
                                <span aria-hidden="true">+</span> Add group
                              </button>
                            </div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                    <div>
                      <button
                        type="button"
                        phx-click="segments_add"
                        class="inline-flex items-center gap-1 rounded-md bg-teal-600 px-3 py-2 text-xs font-semibold text-white shadow-sm hover:bg-teal-500"
                      >
                        <span aria-hidden="true">+</span> Add segment
                      </button>
                    </div>
                  </div>
                  
    <!-- Defaults -->
                  <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
                    <div class="mb-4">
                      <h3 class="text-sm font-semibold text-gray-900 dark:text-white">Defaults</h3>
                      <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                        These values are used as the initial timeframe and granularity when opening this dashboard.
                        Timeframe accepts smart inputs like 24h, 2d, 1w, 1mo. You can override database defaults here.
                      </p>
                    </div>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      <div>
                        <.timeframe_input
                          id="dashboard-default-timeframe"
                          name="timeframe"
                          label="Timeframe"
                          value={
                            @temp_timeframe || @dashboard.default_timeframe ||
                              @database.default_timeframe || "24h"
                          }
                          placeholder="e.g. 24h, 2d, 1w, 1mo, 1y"
                        />
                      </div>
                      <div>
                        <.granularity_select
                          id="dashboard-default-granularity"
                          name="granularity"
                          label="Granularity"
                          wrapper_class="grid grid-cols-1 sm:max-w-xs mt-2"
                          value={
                            @dashboard.default_granularity || @database.default_granularity || "1h"
                          }
                          options={Granularity.options(@available_granularities)}
                          prompt="Use source default"
                        />
                      </div>
                    </div>
                  </div>
                </.form>
              </div>
            </:body>
            <:actions>
              <.form_actions>
                <.secondary_button type="button" phx-click={configure_cancel}>
                  Cancel
                </.secondary_button>
                <.primary_button form="dashboard-configure-form" phx-disable-with="Saving...">
                  Save changes
                </.primary_button>
              </.form_actions>
            </:actions>
            <:below_actions>
              <%= if @can_clone_dashboard do %>
                <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
                  <div class="flex items-center justify-between mb-2">
                    <div>
                      <span class="text-sm font-medium text-gray-700 dark:text-slate-300">
                        Actions
                      </span>
                      <p class="text-xs text-gray-500 dark:text-slate-400">
                        Make a copy of this dashboard.
                      </p>
                    </div>
                    <button
                      type="button"
                      phx-click="duplicate_dashboard"
                      class="inline-flex items-center whitespace-nowrap rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                      title="Duplicate dashboard"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        class="md:-ml-0.5 md:mr-1.5 h-4 w-4"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M15.75 17.25v3.375c0 .621-.504 1.125-1.125 1.125h-9.75a1.125 1.125 0 0 1-1.125-1.125V7.875c0-.621.504-1.125 1.125-1.125H6.75a9.06 9.06 0 0 1 1.5.124m7.5 10.376h3.375c.621 0 1.125-.504 1.125-1.125V11.25c0-4.46-3.243-8.161-7.5-8.876a9.06 9.06 0 0 0-1.5-.124H9.375c-.621 0-1.125.504-1.125 1.125v3.5m7.5 10.375H9.375a1.125 1.125 0 0 1-1.125-1.125v-9.25m12 6.625v-1.875a3.375 3.375 0 0 0-3.375-3.375h-1.5a1.125 1.125 0 0 1-1.125-1.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H9.75"
                        />
                      </svg>
                      <span class="hidden md:inline">Duplicate</span>
                    </button>
                  </div>
                </div>
              <% end %>

              <%= if @can_manage_dashboard do %>
                <div class="border-t border-gray-200 dark:border-slate-600 pt-6 flex items-center justify-between">
                  <div>
                    <span class="text-sm font-medium text-gray-700 dark:text-slate-300">
                      Visibility
                    </span>
                    <p class="text-xs text-gray-500 dark:text-slate-400">
                      Make this dashboard visible to everyone in the organization
                    </p>
                  </div>
                  <button
                    type="button"
                    phx-click="toggle_visibility"
                    class={[
                      "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-teal-600 focus:ring-offset-2",
                      if(@dashboard.visibility,
                        do: "bg-teal-600",
                        else: "bg-gray-200 dark:bg-gray-700"
                      )
                    ]}
                  >
                    <span class={[
                      "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                      if(@dashboard.visibility, do: "translate-x-5", else: "translate-x-0")
                    ]}>
                    </span>
                  </button>
                </div>

                <div class="border-t border-gray-200 dark:border-slate-600 pt-6 flex items-center justify-between">
                  <div>
                    <span class="text-sm font-medium text-gray-700 dark:text-slate-300">Lock</span>
                    <p class="text-xs text-gray-500 dark:text-slate-400">
                      Prevent regular members from editing while locked.
                    </p>
                  </div>
                  <button
                    type="button"
                    phx-click="toggle_lock"
                    disabled={!@can_manage_lock}
                    class={[
                      "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-amber-500 focus:ring-offset-2",
                      if(@dashboard.locked,
                        do: "bg-amber-500 dark:bg-amber-400",
                        else: "bg-gray-200 dark:bg-gray-700"
                      ),
                      if(@can_manage_lock, do: nil, else: "cursor-not-allowed opacity-60")
                    ]}
                  >
                    <span class={[
                      "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                      if(@dashboard.locked, do: "translate-x-5", else: "translate-x-0")
                    ]}>
                    </span>
                  </button>
                </div>

                <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
                  <div class="flex items-center justify-between">
                    <div>
                      <span class="text-sm font-medium text-gray-700 dark:text-slate-300">
                        Public Link
                      </span>
                      <p class="text-xs text-gray-500 dark:text-slate-400">
                        Generate a shareable link for read-only access.
                      </p>
                    </div>
                    <%= if @public_token do %>
                      <div class="flex flex-wrap items-center gap-3">
                        <button
                          type="button"
                          phx-click="copy_public_link"
                          class="inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-slate-800 dark:text-slate-200 dark:ring-slate-600 dark:hover:bg-slate-700"
                        >
                          Copy Public Link
                        </button>
                        <button
                          type="button"
                          phx-click="remove_public_token"
                          data-confirm="Are you sure you want to remove the public link? Anyone with the current link will lose access."
                          class="inline-flex items-center rounded-md bg-red-50 px-3 py-2 text-sm font-semibold text-red-700 ring-1 ring-inset ring-red-600/20 hover:bg-red-100 dark:bg-red-900 dark:text-red-200 dark:ring-red-500/30 dark:hover:bg-red-800"
                        >
                          Remove Link
                        </button>
                      </div>
                    <% else %>
                      <button
                        type="button"
                        phx-click="generate_public_token"
                        class="inline-flex items-center rounded-md bg-teal-50 px-3 py-2 text-sm font-semibold text-teal-700 ring-1 ring-inset ring-teal-600/20 hover:bg-teal-100 dark:bg-teal-900 dark:text-teal-200 dark:ring-teal-500/30 dark:hover:bg-teal-800"
                      >
                        Generate Public Link
                      </button>
                    <% end %>
                  </div>
                </div>

                <div class="border-t border-red-200 dark:border-red-800 pt-6">
                  <div class="mb-4">
                    <span class="text-sm font-medium text-red-700 dark:text-red-400">
                      Danger Zone
                    </span>
                    <p class="text-xs text-red-600 dark:text-red-400">
                      This action cannot be undone.
                    </p>
                  </div>

                  <div
                    :if={
                      @can_transfer_dashboard_owner && Enum.any?(@dashboard_owner_candidates || [])
                    }
                    class="mb-6 space-y-3"
                  >
                    <div>
                      <span class="text-xs font-semibold uppercase tracking-wide text-red-700 dark:text-red-300">
                        Transfer ownership
                      </span>
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        Move ownership to another member. You might lose direct access if you are not an organization admin.
                      </p>
                    </div>
                    <div class="flex flex-wrap items-center gap-2">
                      <.form
                        for={%{}}
                        phx-change="change_dashboard_owner_selection"
                        class="flex flex-1"
                      >
                        <select
                          name="dashboard_owner_membership_id"
                          class="min-w-[12rem] flex-1 rounded-md border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 shadow-sm focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-900 dark:text-white"
                          value={@dashboard_owner_selection || ""}
                        >
                          <option value="">Select member…</option>
                          <%= for candidate <- @dashboard_owner_candidates || [] do %>
                            <option
                              value={candidate.id}
                              selected={@dashboard_owner_selection == candidate.id}
                            >
                              {candidate.label}
                            </option>
                          <% end %>
                        </select>
                      </.form>
                      <button
                        type="button"
                        class="inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-red-700 shadow-sm ring-1 ring-inset ring-red-600/20 transition hover:bg-red-50 dark:bg-red-900 dark:text-red-200 dark:ring-red-500/30 dark:hover:bg-red-800"
                        phx-click="transfer_dashboard_owner"
                        data-confirm="Transfer ownership to the selected member?"
                        disabled={@dashboard_owner_selection in [nil, ""]}
                      >
                        Transfer ownership
                      </button>
                    </div>
                    <p :if={@dashboard_owner_error} class="text-xs text-rose-600 dark:text-rose-400">
                      {@dashboard_owner_error}
                    </p>
                  </div>

                  <button
                    type="button"
                    phx-click="delete_dashboard"
                    data-confirm="Are you sure you want to delete this dashboard? This action cannot be undone."
                    class="w-full inline-flex items-center justify-center rounded-md bg-red-50 dark:bg-red-900 px-3 py-2 text-sm font-medium text-red-700 dark:text-red-200 ring-1 ring-inset ring-red-600/20 dark:ring-red-500/30 hover:bg-red-100 dark:hover:bg-red-800"
                    title="Delete this dashboard"
                  >
                    Delete Dashboard
                  </button>
                </div>
              <% end %>
            </:below_actions>
          </.app_modal>
        <% end %>
        
    <!-- Widget Edit Modal -->
        <%= if !@is_public_access && @editing_widget do %>
          <% widget_cancel = JS.push("close_widget_editor") %>
          <.app_modal id="widget-modal" show={true} on_cancel={widget_cancel}>
            <:title>Edit Widget</:title>
            <:body>
              <div class="space-y-6">
                <.form
                  for={%{}}
                  id="widget-editor-form"
                  phx-change="change_widget_type"
                  phx-submit="save_widget"
                  class="space-y-4"
                >
                  <input type="hidden" name="widget_id" value={@editing_widget["id"]} />
                  <div>
                    <label
                      for="widget_type"
                      class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2"
                    >
                      Widget Type
                    </label>
                    <div class="grid grid-cols-1 sm:max-w-xs mt-2">
                      <select
                        id="widget_type"
                        name="widget_type"
                        class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
                      >
                        <% sel = @editing_widget["type"] || "kpi" %>
                        <option value="kpi" selected={sel == "kpi"}>KPI</option>
                        <option value="timeseries" selected={sel == "timeseries"}>Timeseries</option>
                        <option value="category" selected={sel == "category"}>Category</option>
                        <option value="table" selected={sel == "table"}>Table</option>
                        <option value="list" selected={sel == "list"}>List</option>
                        <option value="text" selected={sel == "text"}>Text</option>
                      </select>
                      <svg
                        viewBox="0 0 16 16"
                        fill="currentColor"
                        data-slot="icon"
                        aria-hidden="true"
                        class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 dark:text-slate-400 sm:h-4 sm:w-4"
                      >
                        <path
                          d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z"
                          clip-rule="evenodd"
                          fill-rule="evenodd"
                        />
                      </svg>
                    </div>
                  </div>
                  <div>
                    <label
                      for="widget_title"
                      class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2"
                    >
                      Title
                    </label>
                    <input
                      type="text"
                      id="widget_title"
                      name="widget_title"
                      value={@editing_widget["title"] || ""}
                      phx-debounce="400"
                      class="flex-1 block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                      placeholder="Widget title"
                    />
                  </div>

                  <WidgetEditor.editor widget={@editing_widget} path_options={@widget_path_options} />
                </.form>
              </div>
            </:body>
            <:actions>
              <.form_actions>
                <.secondary_button type="button" phx-click={widget_cancel}>
                  Cancel
                </.secondary_button>
                <.primary_button form="widget-editor-form" phx-disable-with="Saving...">
                  Save
                </.primary_button>
              </.form_actions>
            </:actions>
            <:below_actions>
              <div class="border-t border-gray-200 dark:border-slate-600 pt-4">
                <h3 class="text-sm font-medium text-red-600 dark:text-red-400">Danger Zone</h3>
                <p class="text-xs text-gray-500 dark:text-slate-400">
                  Delete this widget permanently from the dashboard.
                </p>
                <div class="mt-3">
                  <button
                    type="button"
                    phx-click="delete_widget"
                    phx-value-id={@editing_widget["id"]}
                    data-confirm="Are you sure you want to delete this widget? This action cannot be undone."
                    class="w-full inline-flex items-center justify-center rounded-md bg-red-50 dark:bg-red-900 px-3 py-2 text-sm font-semibold text-red-700 dark:text-red-200 ring-1 ring-inset ring-red-600/20 dark:ring-red-500/30 hover:bg-red-100 dark:hover:bg-red-800"
                  >
                    Delete Widget
                  </button>
                </div>
              </div>
            </:below_actions>
          </.app_modal>
        <% end %>
        
    <!-- Expanded Widget Modal -->
        <%= if @expanded_widget do %>
          <.app_modal
            id="widget-expand-modal"
            show={true}
            size="full"
            on_cancel={JS.push("close_expanded_widget")}
          >
            <:title>
              <div class="flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-3">
                <div class="flex items-center gap-3">
                  <span>{@expanded_widget.title}</span>
                  <span class="inline-flex items-center rounded-full bg-teal-100/70 dark:bg-teal-900/40 px-3 py-0.5 text-xs font-medium text-teal-700 dark:text-teal-200">
                    {String.capitalize(@expanded_widget.type || "widget")}
                  </span>
                </div>
              </div>
            </:title>
            <:body>
              <%= if @expanded_widget.type == "table" do %>
                <% render_table = @expanded_widget[:table_data] %>
                <div class="h-[80vh] flex flex-col gap-6 overflow-y-auto">
                  <div class="flex-1 min-h-[500px] rounded-lg border border-gray-200/80 dark:border-slate-700/60 bg-white dark:bg-slate-900/40 p-4">
                    <%= if render_table do %>
                      <DataTable.table
                        dataset={render_table}
                        transponder_info={@transponder_info || %{}}
                        outer_class="flex-1 flex flex-col min-h-0"
                      />
                    <% else %>
                      <div class="h-full w-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 text-center">
                        Configure this widget with a path to display table data.
                      </div>
                    <% end %>
                  </div>
                </div>
              <% else %>
                <%= if @expanded_widget.type == "list" do %>
                  <% list_data = @expanded_widget[:list_data] %>
                  <div class="h-[80vh] flex flex-col gap-6 overflow-y-auto">
                    <div class="flex-1 min-h-[400px] rounded-lg border border-gray-200/80 dark:border-slate-700/60 bg-white dark:bg-slate-900/40 p-4">
                      <%= if list_data do %>
                        <% items = expanded_list_items(list_data) %>
                        <% empty_message = expanded_list_empty_message(list_data) %>
                        <%= if items == [] do %>
                          <div class="h-full w-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 text-center">
                            {empty_message}
                          </div>
                        <% else %>
                          <div class="h-full w-full overflow-auto">
                            <table class="min-w-full divide-y divide-gray-200 dark:divide-slate-700 text-sm">
                              <tbody class="divide-y divide-gray-100 dark:divide-slate-800 text-gray-900 dark:text-slate-100">
                                <%= for item <- items do %>
                                  <% color = expanded_list_color(item) %>
                                  <% label = expanded_list_label(item) %>
                                  <% value = expanded_list_value(item) %>
                                  <% badge_bg = expanded_list_color_with_alpha(color, "15") %>
                                  <% badge_border = expanded_list_color_with_alpha(color, "40") %>
                                  <tr>
                                    <td class="px-4 py-3 align-middle">
                                      <div class="flex items-center gap-3 min-w-0">
                                        <span
                                          class="inline-flex h-2.5 w-2.5 rounded-full flex-shrink-0"
                                          style={"background-color: #{color}"}
                                          aria-hidden="true"
                                        >
                                        </span>
                                        <div class="min-w-0">
                                          <p
                                            class="font-mono text-xs truncate text-slate-700 dark:text-slate-200"
                                            title={label}
                                          >
                                            {label}
                                          </p>
                                          <p
                                            class="text-[11px] text-slate-500 dark:text-slate-400 truncate"
                                            title={expanded_list_path(item)}
                                          >
                                            {expanded_list_path(item)}
                                          </p>
                                        </div>
                                      </div>
                                    </td>
                                    <td class="px-4 py-3 text-right align-middle">
                                      <span
                                        class="inline-flex items-center rounded-md border px-3 py-1 text-xs font-semibold"
                                        style={
                                          "color: #{color}; border-color: #{badge_border}; background-color: #{badge_bg}"
                                        }
                                      >
                                        {value}
                                      </span>
                                    </td>
                                  </tr>
                                <% end %>
                              </tbody>
                            </table>
                          </div>
                        <% end %>
                      <% else %>
                        <div class="h-full w-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 text-center">
                          Configure this widget with a path to display list data.
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% else %>
                  <% chart_data = @expanded_widget[:chart_data] %>
                  <% visual_data = @expanded_widget[:visual_data] %>
                  <% text_data = @expanded_widget[:text_data] %>
                  <div
                    id={"expanded-widget-#{@expanded_widget.widget_id}"}
                    class="h-[80vh] flex flex-col gap-6 overflow-y-auto"
                    phx-hook="ExpandedWidgetView"
                    data-type={@expanded_widget.type}
                    data-title={@expanded_widget.title}
                    data-colors={ChartColors.json_palette()}
                    data-chart={if chart_data, do: Jason.encode!(chart_data)}
                    data-visual={if visual_data, do: Jason.encode!(visual_data)}
                    data-text={if text_data, do: Jason.encode!(text_data)}
                  >
                    <div class="flex-1 min-h-[500px]">
                      <div class="h-full w-full rounded-lg border border-gray-200/80 dark:border-slate-700/60 bg-white dark:bg-slate-900/40 p-4">
                        <div data-role="chart" class="h-full w-full"></div>
                      </div>
                    </div>
                    <div class="flex-1 min-h-[300px] rounded-lg border border-gray-200/80 dark:border-slate-700/60 bg-white dark:bg-slate-900/60 overflow-auto">
                      <div data-role="table-root" class="h-full w-full overflow-auto"></div>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </:body>
          </.app_modal>
        <% end %>
        
    <!-- Dashboard Content -->
        <div class="flex-1 relative">
          <%= if !has_grid_items do %>
            <!-- Empty state in white panel -->
            <div class="bg-white dark:bg-slate-800 rounded-lg shadow relative">
              <div class="p-6">
                <!-- Empty state -->
                <div class="text-center py-12">
                  <svg
                    class="mx-auto h-12 w-12 text-gray-400"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    aria-hidden="true"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M3.75 3v11.25A2.25 2.25 0 0 0 6 16.5h2.25M3.75 3h-1.5m1.5 0h16.5m0 0h1.5m-1.5 0v11.25A2.25 2.25 0 0 1 18 16.5h-2.25m-7.5 0h7.5m-7.5 0-1 3m8.5-3 1 3m0 0 .5 1.5m-.5-1.5h-9.5m0 0-.5 1.5M9 11.25v1.5M12 9v3.75m3-6v6"
                    />
                  </svg>
                  <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
                    Dashboard is empty
                  </h3>
                  <p class="mt-1 text-sm text-gray-500 dark:text-slate-400">
                    This dashboard doesn&#39;t have any visualization data yet. Hit the Add Widget button and give it something to show off.
                  </p>
                  <%= if !@is_public_access do %>
                    <% add_btn_id = "dashboard-" <> @dashboard.id <> "-add-widget" %>
                    <div class="mt-6">
                      <button
                        type="button"
                        phx-click={JS.dispatch("click", to: "##{add_btn_id}")}
                        class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
                      >
                        <svg
                          class="-ml-0.5 mr-1.5 h-5 w-5"
                          xmlns="http://www.w3.org/2000/svg"
                          fill="none"
                          viewBox="0 0 24 24"
                          stroke-width="1.5"
                          stroke="currentColor"
                        >
                          <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v12m6-6H6" />
                        </svg>
                        Add Widget
                      </button>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </main>
      
    <!-- Sticky Summary Footer for authenticated users -->
      <%= if !@is_public_access do %>
        <%= if summary = get_summary_stats(assigns) do %>
          <.dashboard_footer
            class="mt-auto"
            summary={summary}
            load_duration_microseconds={@load_duration_microseconds}
            show_export_dropdown={@show_export_dropdown}
            dashboard={@dashboard}
            export_params={export_params}
          />
        <% end %>
      <% end %>
    </div>
    """
  end

  defp group_sources_for_select(sources) do
    sources
    |> Enum.group_by(&Source.type/1)
    |> Enum.map(fn {type, list} -> {Source.type_label(type), list} end)
    |> Enum.sort_by(fn {label, _} -> label end)
  end

  defp source_option_value(source) do
    type = source |> Source.type() |> Atom.to_string()
    id = source |> Source.id() |> to_string()
    "#{type}:#{id}"
  end

  defp source_selected?(nil, _source), do: false

  defp source_selected?(%{type: type, id: id}, source) do
    type == Source.type(source) && id == to_string(Source.id(source))
  end

  defp expanded_list_items(data) when is_map(data) do
    Map.get(data, :items) || Map.get(data, "items") || []
  end

  defp expanded_list_items(_), do: []

  defp expanded_list_empty_message(data) when is_map(data) do
    Map.get(data, :empty_message) || Map.get(data, "empty_message") || "No data available yet."
  end

  defp expanded_list_empty_message(_), do: "No data available yet."

  defp expanded_list_color(item) do
    Map.get(item, :color) || Map.get(item, "color") || ChartColors.primary()
  end

  defp expanded_list_label(item) do
    Map.get(item, :label) || Map.get(item, "label") || expanded_list_path(item) || "Item"
  end

  defp expanded_list_path(item) do
    Map.get(item, :path) || Map.get(item, "path") || ""
  end

  defp expanded_list_value(item) do
    Map.get(item, :formatted_value) ||
      Map.get(item, "formatted_value") ||
      Map.get(item, :value) ||
      Map.get(item, "value") ||
      "0"
  end

  defp expanded_list_color_with_alpha(color, alpha_suffix) do
    cond do
      is_binary(color) and String.starts_with?(color, "#") ->
        color <> alpha_suffix

      true ->
        color || ChartColors.primary()
    end
  end
end
