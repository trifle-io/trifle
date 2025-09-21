defmodule TrifleApp.Components.DashboardFooter do
  @moduledoc """
  Sticky summary footer for the dashboard view.

  Extracted from `TrifleApp.DashboardLive` to keep the LiveView template focused
  on high-level layout concerns while preserving the interactive controls.
  """
  use TrifleApp, :html

  alias TrifleApp.DashboardLive

  attr :summary, :map, required: true
  attr :load_duration_microseconds, :integer, default: nil
  attr :show_export_dropdown, :boolean, default: false
  attr :dashboard, :map, required: true
  attr :export_params, :map, required: true
  attr :class, :string, default: nil
  attr :rest, :global

  def dashboard_footer(assigns) do
    ~H"""
    <div
      class={[
        "sticky bottom-0 w-full border-t border-gray-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-4 py-3 shadow-lg z-30",
        @class
      ]}
      {@rest}
    >
      <% summary = @summary %>
      <div class="flex flex-wrap items-center gap-4 text-xs">
        <div class="flex items-center gap-1 text-gray-600 dark:text-slate-300">
          <svg
            class="h-4 w-4 text-teal-500"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M12 3c2.755 0 5.455.232 8.083.678.533.09.917.556.917 1.096v1.044a2.25 2.25 0 0 1-.659 1.591l-5.432 5.432a2.25 2.25 0 0 0-.659 1.591v2.927a2.25 2.25 0 0 1-1.244 2.013L9.75 21v-6.568a2.25 2.25 0 0 0-.659-1.591L3.659 7.409A2.25 2.25 0 0 1 3 5.818V4.774c0-.54.384-1.006.917-1.096A48.32 48.32 0 0 1 12 3Z"
            />
          </svg>
          <span class="font-medium">Key:</span>
          <span class="truncate max-w-32" title={summary.key}>{summary.key}</span>
        </div>

        <%= if summary.column_count > 0 do %>
          <div class="flex items-center gap-1 text-gray-600 dark:text-slate-300">
            <svg
              class="h-4 w-4 text-teal-500"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 0 1 3 19.875v-6.75ZM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V8.625ZM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V4.125Z"
              />
            </svg>
            <span class="font-medium">Points:</span>
            <span>{summary.column_count}</span>
          </div>
        <% end %>

        <%= if summary.path_count > 0 do %>
          <div class="flex items-center gap-1 text-gray-600 dark:text-slate-300">
            <svg
              class="h-4 w-4 text-teal-500"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M8.25 6.75h12M8.25 12h12m-12 5.25h12M3.75 6.75h.007v.008H3.75V6.75Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0ZM3.75 12h.007v.008H3.75V12Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Zm-.375 5.25h.007v.008H3.75v-.008Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Z"
              />
            </svg>
            <span class="font-medium">Paths:</span>
            <span>{summary.path_count}</span>
          </div>
        <% end %>

        <div class="flex items-center gap-1">
          <svg
            class="h-4 w-4 text-teal-500"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="m21 7.5-2.25-1.313M21 7.5v2.25m0-2.25-2.25 1.313M3 7.5l2.25-1.313M3 7.5l2.25 1.313M3 7.5v2.25m9 3 2.25-1.313M12 12.75l-2.25-1.313M12 12.75V15m0 6.75 2.25-1.313M12 21.75V19.5m0 2.25-2.25-1.313m0-16.875L12 2.25l2.25 1.313M21 14.25v2.25l-2.25 1.313m-13.5 0L3 16.5v-2.25"
            />
          </svg>
          <span class="font-medium text-gray-700 dark:text-slate-300">Transponders:</span>
          <div class="flex items-center gap-1">
            <svg
              class="h-3 w-3 text-green-600"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
              />
            </svg>
            <span class="text-gray-900 dark:text-white">{summary.successful_transponders}</span>
          </div>
          <div class="flex items-center gap-1">
            <svg
              class="h-3 w-3 text-red-500"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z"
              />
            </svg>
            <%= if summary.failed_transponders > 0 do %>
              <button
                phx-click="show_transponder_errors"
                class="text-red-600 dark:text-red-400 hover:text-red-800 dark:hover:text-red-300 underline"
              >
                {summary.failed_transponders}
              </button>
            <% else %>
              <span class="text-gray-900 dark:text-white">0</span>
            <% end %>
          </div>
        </div>

        <%= if @load_duration_microseconds do %>
          <div class="flex items-center gap-1 text-gray-600 dark:text-slate-300">
            <svg
              class="h-4 w-4 text-teal-500"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="m3.75 13.5 10.5-11.25L12 10.5h8.25L9.75 21.75 12 13.5H3.75Z"
              />
            </svg>
            <span class="font-medium">Load:</span>
            <span>{DashboardLive.format_duration(@load_duration_microseconds)}</span>
          </div>
        <% end %>

        <div
          id="dashboard-download-menu"
          class="ml-auto relative"
          data-default-label="Export"
          phx-hook="DownloadMenu"
        >
          <button
            type="button"
            phx-click="toggle_export_dropdown"
            data-role="download-button"
            class="inline-flex items-center rounded-md bg-white dark:bg-slate-700 px-2.5 py-1.5 text-xs font-medium text-gray-700 dark:text-slate-200 shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-4 w-4 mr-1 text-teal-600 dark:text-teal-400"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
              />
            </svg>
            <span class="inline" data-role="download-text">Export</span>
            <svg
              class="ml-1 h-3 w-3 text-gray-500 dark:text-slate-400"
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 20 20"
              fill="currentColor"
            >
              <path
                fill-rule="evenodd"
                d="M5.23 7.21a.75.75 0 0 1 1.06.02L10 10.94l3.71-3.71a.75.75 0 0 1 1.08 1.04l-4.25 4.5a.75.75 0 0 1-1.08 0l-4.25-4.5a.75.75 0 0 1 .02-1.06z"
                clip-rule="evenodd"
              />
            </svg>
          </button>

          <%= if @show_export_dropdown do %>
            <% export_params = @export_params %>
            <div
              data-role="download-dropdown"
              class="absolute bottom-9 right-0 w-48 bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-md shadow-lg py-1 z-40"
              phx-click-away="hide_export_dropdown"
            >
              <a
                data-export-link
                onclick="(function(el){var m=el.closest('#dashboard-download-menu');if(!m)return;var d=m.querySelector('[data-role=download-dropdown]');if(d)d.style.display='none';var b=m.querySelector('[data-role=download-button]');var t=m.querySelector('[data-role=download-text]');if(b){b.disabled=true;b.classList.add('opacity-70','cursor-wait');}if(t){t.textContent='Generating...';}try{var u=new URL(el.href, window.location.origin);if(!u.searchParams.get('download_token')){var token=Date.now()+'-'+Math.random().toString(36).slice(2);window.__downloadToken=token;u.searchParams.set('download_token', token);el.href=u.toString();}}catch(_){} })(this)"
                href={~p"/export/dashboards/#{@dashboard.id}/csv?#{export_params}"}
                target="download_iframe"
                class="w-full block px-3 py-2 text-xs text-gray-700 dark:text-slate-200 hover:bg-gray-100 dark:hover:bg-slate-700"
              >
                <span class="flex items-center">
                  <svg
                    class="h-4 w-4 mr-2 text-teal-600 dark:text-teal-400"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
                    />
                  </svg>
                  CSV (table)
                </span>
              </a>
              <a
                data-export-link
                onclick="(function(el){var m=el.closest('#dashboard-download-menu');if(!m)return;var d=m.querySelector('[data-role=download-dropdown]');if(d)d.style.display='none';var b=m.querySelector('[data-role=download-button]');var t=m.querySelector('[data-role=download-text]');if(b){b.disabled=true;b.classList.add('opacity-70','cursor-wait');}if(t){t.textContent='Generating...';}try{var u=new URL(el.href, window.location.origin);if(!u.searchParams.get('download_token')){var token=Date.now()+'-'+Math.random().toString(36).slice(2);window.__downloadToken=token;u.searchParams.set('download_token', token);el.href=u.toString();}}catch(_){} })(this)"
                href={~p"/export/dashboards/#{@dashboard.id}/json?#{export_params}"}
                target="download_iframe"
                class="w-full block px-3 py-2 text-xs text-gray-700 dark:text-slate-200 hover:bg-gray-100 dark:hover:bg-slate-700"
              >
                <span class="flex items-center">
                  <svg
                    class="h-4 w-4 mr-2 text-indigo-600 dark:text-indigo-400"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
                    />
                  </svg>
                  JSON (raw)
                </span>
              </a>
              <a
                data-export-link
                onclick="(function(el){var m=el.closest('#dashboard-download-menu');if(!m)return;var d=m.querySelector('[data-role=download-dropdown]');if(d)d.style.display='none';var b=m.querySelector('[data-role=download-button]');var t=m.querySelector('[data-role=download-text]');if(b){b.disabled=true;b.classList.add('opacity-70','cursor-wait');}if(t){t.textContent='Generating...';}try{var u=new URL(el.href, window.location.origin);if(!u.searchParams.get('download_token')){var token=Date.now()+'-'+Math.random().toString(36).slice(2);window.__downloadToken=token;u.searchParams.set('download_token', token);el.href=u.toString();}}catch(_){} })(this)"
                href={~p"/export/dashboards/#{@dashboard.id}/pdf?#{export_params}"}
                target="download_iframe"
                class="w-full block px-3 py-2 text-xs text-gray-700 dark:text-slate-200 hover:bg-gray-100 dark:hover:bg-slate-700"
              >
                <span class="flex items-center">
                  <svg
                    class="h-4 w-4 mr-2 text-rose-600 dark:text-rose-400"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
                    />
                  </svg>
                  PDF (print)
                </span>
              </a>
              <a
                data-export-link
                onclick="(function(el){var m=el.closest('#dashboard-download-menu');if(!m)return;var d=m.querySelector('[data-role=download-dropdown]');if(d)d.style.display='none';var b=m.querySelector('[data-role=download-button]');var t=m.querySelector('[data-role=download-text]');if(b){b.disabled=true;b.classList.add('opacity-70','cursor-wait');}if(t){t.textContent='Generating...';}try{var u=new URL(el.href, window.location.origin);if(!u.searchParams.get('download_token')){var token=Date.now()+'-'+Math.random().toString(36).slice(2);window.__downloadToken=token;u.searchParams.set('download_token', token);el.href=u.toString();}}catch(_){} })(this)"
                href={
                  ~p"/export/dashboards/#{@dashboard.id}/png?#{Map.put(export_params, "theme", "light")}"
                }
                target="download_iframe"
                class="w-full block px-3 py-2 text-xs text-gray-700 dark:text-slate-200 hover:bg-gray-100 dark:hover:bg-slate-700"
              >
                <span class="flex items-center">
                  <svg
                    class="h-4 w-4 mr-2 text-amber-600 dark:text-amber-400"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
                    />
                  </svg>
                  PNG (light)
                </span>
              </a>
              <a
                data-export-link
                onclick="(function(el){var m=el.closest('#dashboard-download-menu');if(!m)return;var d=m.querySelector('[data-role=download-dropdown]');if(d)d.style.display='none';var b=m.querySelector('[data-role=download-button]');var t=m.querySelector('[data-role=download-text]');if(b){b.disabled=true;b.classList.add('opacity-70','cursor-wait');}if(t){t.textContent='Generating...';}try{var u=new URL(el.href, window.location.origin);if(!u.searchParams.get('download_token')){var token=Date.now()+'-'+Math.random().toString(36).slice(2);window.__downloadToken=token;u.searchParams.set('download_token', token);el.href=u.toString();}}catch(_){} })(this)"
                href={
                  ~p"/export/dashboards/#{@dashboard.id}/png?#{Map.put(export_params, "theme", "dark")}"
                }
                target="download_iframe"
                class="w-full block px-3 py-2 text-xs text-gray-700 dark:text-slate-200 hover:bg-gray-100 dark:hover:bg-slate-700"
              >
                <span class="flex items-center">
                  <svg
                    class="h-4 w-4 mr-2 text-amber-600 dark:text-amber-400"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
                    />
                  </svg>
                  PNG (dark)
                </span>
              </a>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
