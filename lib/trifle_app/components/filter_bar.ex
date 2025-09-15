defmodule TrifleApp.Components.FilterBar do
  @moduledoc """
  Reusable filter bar component for timeframe, controls, and granularity selection.
  
  Handles URL state management and provides a consistent filtering experience
  across different LiveView pages.
  """
  use TrifleApp, :live_component
  
  alias Trifle.Organizations.Database
  alias Trifle.Organizations.Project
  alias TrifleApp.TimeframeParsing
  # Optional: databases and selected_database_id assigns can be passed by parent LiveView
  
  def render(assigns) do
    ~H"""
    <div class="sticky top-0 z-50 mb-6">
      <div class="bg-white dark:bg-slate-800 rounded-lg shadow p-4">
        <div class="flex flex-col md:flex-row md:flex-wrap lg:flex-nowrap md:items-start lg:items-center gap-3 lg:gap-4">
        
        <!-- Database Dropdown (optional; only if >1 DB) -->
        <%= if @databases && length(@databases) > 1 do %>
          <div class="w-full md:w-64">
            <div class="relative">
              <div class="absolute -top-2 left-2 inline-block bg-white dark:bg-slate-800 px-1 text-xs font-medium text-gray-900 dark:text-white z-10">
                Database
              </div>
              <button
                type="button"
                phx-target={@myself}
                phx-click="toggle_database_dropdown"
                class="relative w-full h-10 cursor-default rounded-md border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-700 py-2 pl-3 pr-10 text-left text-sm font-medium text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500"
              >
                <div class="flex items-center justify-between">
                  <span class="truncate">
                    <%= (
                      case Enum.find(@databases, fn d -> to_string(d.id) == to_string(@selected_database_id) end) do
                        nil -> "Select a database"
                        db -> db.display_name
                      end
                    ) %>
                  </span>
                </div>
                <span class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-2">
                  <svg class="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                  </svg>
                </span>
              </button>

              <%= if @show_database_dropdown do %>
                <div
                  phx-click-away="hide_database_dropdown"
                  phx-target={@myself}
                  class="absolute z-50 mt-1 w-full max-h-60 overflow-auto rounded-md bg-white dark:bg-slate-700 py-1 text-base shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none sm:text-sm"
                >
                  <%= for db <- @databases do %>
                    <button
                      type="button"
                      phx-target={@myself}
                      phx-click="select_database"
                      phx-value-id={db.id}
                      onmousedown="event.preventDefault()"
                      class={[
                        "w-full text-left px-4 py-2 hover:bg-gray-100 dark:hover:bg-slate-600 cursor-pointer",
                        to_string(db.id) == to_string(@selected_database_id) && "font-semibold text-teal-600 dark:text-teal-400"
                      ]}
                    >
                      <div class="flex items-center justify-between">
                        <span class="text-sm text-gray-900 dark:text-white truncate"><%= db.display_name %></span>
                      </div>
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <!-- Timeframe Input Section -->
        <div class="w-full md:w-full lg:w-[26rem]">
          <div class="relative">
            <div class="relative">
              <.labeled_input
                label={"Timeframe #{@config.time_zone || "UTC"}#{TimeframeParsing.get_timezone_offset_display(@config.time_zone || "UTC")}"}
                id="smart_timeframe"
                name="smart_timeframe"
                value={@current_input_value}
                placeholder="e.g., 5m, 2h, 1d, 3w, 6mo, 1y or YYYY-MM-DD HH:MM:SS - YYYY-MM-DD HH:MM:SS"
                phx-target={@myself}
                phx-keydown="smart_timeframe_keydown"
                phx-keyup="smart_timeframe_keyup"
                phx-click="toggle_timeframe_dropdown"
                phx-hook="SmartTimeframeBlur"
              />
              <span class="pointer-events-none absolute top-1/2 right-12 transform -translate-y-1/2">
                <span class="inline-flex items-center rounded-md bg-teal-100 dark:bg-teal-900/30 px-2 py-1 text-xs font-medium text-teal-600 dark:text-teal-400 ring-1 ring-inset ring-gray-500/10 dark:ring-slate-600/50">
                  <%= @smart_timeframe_input || "24h" %>
                </span>
              </span>
              <span class="pointer-events-none absolute top-1/2 right-3 transform -translate-y-1/2">
                <svg class="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                </svg>
              </span>
            </div>
            
            <!-- Timeframe Dropdown -->
            <%= if @show_timeframe_dropdown do %>
              <div 
                phx-click-away="hide_timeframe_dropdown"
                phx-target={@myself}
                class="absolute top-full left-0 right-0 mt-1 bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-md shadow-lg z-20"
              >
                <div class="px-3 py-2 border-b border-gray-200 dark:border-slate-700">
                  <h6 class="text-xs font-semibold uppercase text-gray-500 dark:text-slate-400">Quick Timeframes</h6>
                </div>
                <div class="py-1">
                  <%= for {preset, label} <- TimeframeParsing.timeframe_presets() do %>
                    <button 
                      type="button"
                      phx-target={@myself}
                      phx-click="select_timeframe_preset"
                      phx-value-preset={preset}
                      phx-value-label={label}
                      class="w-full text-left px-3 py-2 text-sm text-gray-900 dark:text-white hover:bg-gray-100 dark:hover:bg-slate-700"
                    >
                      <div class="flex items-center justify-between">
                        <span><%= label %></span>
                        <span class="inline-flex items-center rounded-md bg-teal-100 dark:bg-teal-900/30 px-2 py-1 text-xs font-medium text-teal-600 dark:text-teal-400 ring-1 ring-inset ring-gray-500/10 dark:ring-slate-600/50">
                          <%= preset %>
                        </span>
                      </div>
                    </button>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </div>
        
        <!-- Controls and Granularity Section -->
        <div class="flex items-center gap-4 flex-shrink-0 md:w-full md:justify-end lg:w-auto lg:ml-auto">
          <!-- Controls Section -->
          <%= if @show_controls do %>
            <div id="controls-container" phx-hook="FastTooltip">
              <.button_group label="Controls">
              <:button phx-target={@myself} phx-click="navigate_timeframe_backward" data-tooltip="Move timeframe backward in time">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M21 16.811c0 .864-.933 1.406-1.683.977l-7.108-4.061a1.125 1.125 0 0 1 0-1.954l7.108-4.061A1.125 1.125 0 0 1 21 8.689v8.122ZM11.25 16.811c0 .864-.933 1.406-1.683.977l-7.108-4.061a1.125 1.125 0 0 1 0-1.954l7.108-4.061a1.125 1.125 0 0 1 1.683.977v8.122Z" />
                </svg>
              </:button>
              <:button phx-target={@myself} phx-click="reload_data" data-tooltip="Refresh data for current timeframe">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0l3.181 3.183a8.25 8.25 0 0013.803-3.7M4.031 9.865a8.25 8.25 0 0113.803-3.7l3.181 3.182m0-4.991v4.99" />
                </svg>
              </:button>
              <:button phx-target={@myself} phx-click="toggle_play_pause" selected={!@use_fixed_display} data-tooltip={if @use_fixed_display, do: "Play (auto-update)", else: "Pause (freeze range)"}>
                <%= if @use_fixed_display do %>
                  <!-- Currently Paused: show Play icon, normal background -->
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M5.25 5.653c0-.856.917-1.398 1.667-.986l11.54 6.347a1.125 1.125 0 0 1 0 1.972l-11.54 6.347a1.125 1.125 0 0 1-1.667-.986V5.653Z" />
                  </svg>
                <% else %>
                  <!-- Currently Playing: show Pause icon, teal selected background provided by selected=true -->
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 5.25v13.5m-7.5-13.5v13.5" />
                  </svg>
                <% end %>
              </:button>
              <:button phx-target={@myself} phx-click="navigate_timeframe_forward" data-tooltip="Move timeframe forward in time">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M3 8.689c0-.864.933-1.406 1.683-.977l7.108 4.061a1.125 1.125 0 0 1 0 1.954l-7.108 4.061A1.125 1.125 0 0 1 3 16.811V8.69ZM12.75 8.689c0-.864.933-1.406 1.683-.977l7.108 4.061a1.125 1.125 0 0 1 0 1.954l-7.108 4.061a1.125 1.125 0 0 1-1.683-.977V8.69Z" />
                </svg>
              </:button>
            </.button_group>
            </div>
          <% end %>
          
          <!-- Granularity Section -->
          <!-- Button Group for large screens -->
          <div class="hidden md:block" id="granularity-container" phx-hook="FastTooltip">
            <%= render_granularity_button_group(assigns) %>
          </div>
          
          <!-- Dropdown for small screens -->
          <div class="block md:hidden">
            <div class="relative">
              <div class="absolute -top-2 left-2 inline-block bg-white dark:bg-slate-800 px-1 text-xs font-medium text-gray-900 dark:text-white z-10">
                Granularity
              </div>
              <button
                type="button"
                phx-target={@myself}
                phx-click="toggle_granularity_dropdown"
                class="relative w-40 h-10 cursor-default rounded-md border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-700 py-2 pl-3 pr-10 text-left text-sm font-medium text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500"
              >
                <div class="flex items-center justify-between">
                  <span><%= granularity_display_name(@granularity) %></span>
                  <span class="inline-flex items-center rounded-md bg-teal-100 dark:bg-teal-900/30 px-2 py-1 text-xs font-medium text-teal-600 dark:text-teal-400 ring-1 ring-inset ring-gray-500/10 dark:ring-slate-600/50">
                    <%= @granularity %>
                  </span>
                </div>
                <span class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-2">
                  <svg class="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                  </svg>
                </span>
              </button>
              
              <%= if @show_granularity_dropdown do %>
                <div 
                  phx-click-away="hide_granularity_dropdown"
                  phx-target={@myself}
                  class="absolute z-50 mt-1 w-40 max-h-60 overflow-auto rounded-md bg-white dark:bg-slate-700 py-1 text-base shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none sm:text-sm"
                >
                  <%= for granularity <- @available_granularities do %>
                    <button
                      type="button"
                      phx-target={@myself}
                      phx-click="select_granularity"
                      phx-value-granularity={granularity}
                      onmousedown="event.preventDefault()"
                      class="w-full text-left px-4 py-2 hover:bg-gray-100 dark:hover:bg-slate-600 cursor-pointer"
                    >
                      <div class="flex items-center justify-between">
                        <span class="text-sm text-gray-900 dark:text-white"><%= granularity_display_name(granularity) %></span>
                        <span class="inline-flex items-center rounded-md bg-teal-100 dark:bg-teal-900/30 px-2 py-1 text-xs font-medium text-teal-600 dark:text-teal-400 ring-1 ring-inset ring-gray-500/10 dark:ring-slate-600/50">
                          <%= granularity %>
                        </span>
                      </div>
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
        
        </div>
      </div>
    </div>
    """
  end
  
  # Component Lifecycle
  
  def mount(socket) do
    {:ok, socket}
  end
  
  def update(assigns, socket) do
    # Check if this is a navigation update (from/to changed but input is the same)
    current_from = socket.assigns[:from]
    current_to = socket.assigns[:to]
    new_from = assigns.from
    new_to = assigns.to
    
    is_navigation_update = (current_from != new_from || current_to != new_to) && 
                          socket.assigns[:current_input_value] != nil
    
    current_input = if is_navigation_update do
      # Navigation controls changed the timeframe - update the input display
      get_input_value(assigns.smart_timeframe_input, assigns.use_fixed_display, assigns.from, assigns.to)
    else
      # Normal update - preserve user typing
      socket.assigns[:current_input_value] || get_input_value(assigns.smart_timeframe_input, assigns.use_fixed_display, assigns.from, assigns.to)
    end
    
    socket = 
      socket
      |> assign(assigns)
      |> assign(databases: Map.get(assigns, :databases, socket.assigns[:databases] || nil))
      |> assign(selected_database_id: Map.get(assigns, :selected_database_id, socket.assigns[:selected_database_id] || nil))
      |> assign(current_input_value: current_input)

    # Ensure database dropdown visibility flag exists (component manages it internally)
    socket = if Map.has_key?(socket.assigns, :show_database_dropdown), do: socket, else: assign(socket, show_database_dropdown: false)

    {:ok, socket}
  end
  
  # Event Handlers
  
  def handle_event("smart_timeframe_keyup", %{"key" => "Enter", "value" => _input}, socket) do
    # Skip keyup for Enter key - already handled by keydown
    {:noreply, socket}
  end
  
  def handle_event("smart_timeframe_keyup", %{"value" => input}, socket) do
    # Update local input state on every keystroke without notifying parent
    {:noreply, assign(socket, current_input_value: input)}
  end
  
  def handle_event("smart_timeframe_keydown", %{"key" => "Enter", "value" => input}, socket) do
    case TimeframeParsing.parse_smart_timeframe(input, socket.assigns.config) do
      {:ok, from, to, smart_input, use_fixed} ->
        # Always show full datetime format in input after submission
        input_value = TimeframeParsing.format_timeframe_display(from, to)
        
        notify_parent({:filter_changed, %{
          from: from, 
          to: to, 
          smart_timeframe_input: smart_input,
          use_fixed_display: use_fixed
        }})
        
        # Force input update by pushing to client
        {:noreply, 
         socket
         |> assign(show_timeframe_dropdown: false, current_input_value: input_value)
         |> push_event("update_timeframe_input", %{value: input_value})}
        
      {:error, _reason} ->
        # Keep current values on parse error
        {:noreply, assign(socket, show_timeframe_dropdown: false)}
    end
  end
  
  def handle_event("smart_timeframe_keydown", %{"key" => _other_key, "value" => _input}, socket) do
    # Handle other keys (Arrow keys, etc.) without action
    {:noreply, socket}
  end
  
  def handle_event("select_timeframe_preset", %{"preset" => preset, "label" => _label}, socket) do
    case TimeframeParsing.parse_smart_timeframe(preset, socket.assigns.config) do
      {:ok, from, to, smart_input, use_fixed} ->
        # Show full datetime format in input, but keep original use_fixed for badge
        input_value = TimeframeParsing.format_timeframe_display(from, to)
        
        notify_parent({:filter_changed, %{
          from: from, 
          to: to, 
          smart_timeframe_input: smart_input,
          use_fixed_display: use_fixed
        }})
        
        {:noreply, 
         socket
         |> assign(show_timeframe_dropdown: false, current_input_value: input_value)
         |> push_event("update_timeframe_input", %{value: input_value})}
        
      {:error, _reason} ->
        {:noreply, assign(socket, show_timeframe_dropdown: false)}
    end
  end
  
  def handle_event("select_granularity", %{"granularity" => granularity}, socket) do
    notify_parent({:filter_changed, %{granularity: granularity}})
    {:noreply, assign(socket, show_granularity_dropdown: false)}
  end

  def handle_event("toggle_database_dropdown", _params, socket) do
    {:noreply, assign(socket, show_database_dropdown: !socket.assigns[:show_database_dropdown])}
  end

  def handle_event("hide_database_dropdown", _params, socket) do
    {:noreply, assign(socket, show_database_dropdown: false)}
  end

  def handle_event("select_database", %{"id" => database_id}, socket) do
    notify_parent({:filter_changed, %{database_id: database_id}})
    {:noreply, assign(socket, show_database_dropdown: false, selected_database_id: database_id)}
  end
  
  def handle_event("toggle_granularity_dropdown", _params, socket) do
    {:noreply, assign(socket, show_granularity_dropdown: !socket.assigns.show_granularity_dropdown)}
  end
  
  def handle_event("hide_granularity_dropdown", _params, socket) do
    {:noreply, assign(socket, show_granularity_dropdown: false)}
  end
  
  def handle_event("toggle_timeframe_dropdown", _params, socket) do
    {:noreply, assign(socket, show_timeframe_dropdown: !socket.assigns.show_timeframe_dropdown)}
  end
  
  def handle_event("hide_timeframe_dropdown", _params, socket) do
    {:noreply, assign(socket, show_timeframe_dropdown: false)}
  end
  
  def handle_event("show_timeframe_dropdown", _params, socket) do
    {:noreply, assign(socket, show_timeframe_dropdown: true)}
  end
  
  def handle_event("delayed_hide_timeframe_dropdown", _params, socket) do
    # Add small delay to allow clicking on dropdown items
    Process.send_after(self(), {:hide_timeframe_dropdown, socket.assigns.id}, 150)
    {:noreply, socket}
  end
  
  def handle_event("navigate_timeframe_backward", _params, socket) do
    {from, to} = TimeframeParsing.calculate_previous_timeframe(socket.assigns.from, socket.assigns.to)
    notify_parent({:filter_changed, %{from: from, to: to, use_fixed_display: true}})
    {:noreply, socket}
  end
  
  def handle_event("navigate_timeframe_forward", _params, socket) do
    # Propose next window
    {new_from, new_to} = TimeframeParsing.calculate_next_timeframe(socket.assigns.from, socket.assigns.to)

    # Clamp to current time in configured timezone to avoid going into the future
    config = socket.assigns.config
    now = DateTime.utc_now() |> DateTime.shift_zone!(config.time_zone || "UTC")
    duration = DateTime.diff(socket.assigns.to, socket.assigns.from, :second)

    {from, to} =
      case DateTime.compare(new_to, now) do
        :gt ->
          to = now
          from = DateTime.add(to, -duration, :second)
          {from, to}
        _ -> {new_from, new_to}
      end

    notify_parent({:filter_changed, %{from: from, to: to, use_fixed_display: true}})
    {:noreply, socket}
  end

  def handle_event("toggle_play_pause", _params, socket) do
    # Toggle between play (use_fixed_display=false) and pause (use_fixed_display=true)
    if socket.assigns.use_fixed_display do
      # Switch to Play: recompute latest from/to from smart_timeframe_input
      tf = socket.assigns.smart_timeframe_input || "24h"
      case TimeframeParsing.parse_smart_timeframe(tf, socket.assigns.config) do
        {:ok, from, to, _smart, _use_fixed} ->
          notify_parent({:filter_changed, %{from: from, to: to, use_fixed_display: false}})
          {:noreply, socket}
        {:error, _} ->
          # Fallback: keep current range but mark as play
          notify_parent({:filter_changed, %{use_fixed_display: false}})
          {:noreply, socket}
      end
    else
      # Switch to Pause: keep current from/to
      notify_parent({:filter_changed, %{use_fixed_display: true}})
      {:noreply, socket}
    end
  end
  
  def handle_event("reload_data", _params, socket) do
    notify_parent({:filter_changed, %{reload: true}})
    {:noreply, socket}
  end
  
  def handle_info({:hide_timeframe_dropdown, component_id}, socket) do
    if socket.assigns.id == component_id do
      {:noreply, assign(socket, show_timeframe_dropdown: false)}
    else
      {:noreply, socket}
    end
  end
  
  # Helper Functions
  
  defp notify_parent(message) do
    send(self(), {:filter_bar, message})
  end
  
  
  defp get_input_value(smart_timeframe_input, use_fixed_display, from, to) do
    cond do
      # Always show the datetime range if we have from/to dates
      from && to ->
        TimeframeParsing.format_timeframe_display(from, to)
      
      # Fallback to shorthand if no dates available
      smart_timeframe_input ->
        smart_timeframe_input
      
      # Default fallback
      true ->
        "24h"
    end
  end

  defp granularity_display_name(granularity) do
    try do
      parser = Trifle.Stats.Nocturnal.Parser.new(granularity)
      
      if Trifle.Stats.Nocturnal.Parser.valid?(parser) do
        unit_name = case parser.unit do
          :second -> if parser.offset == 1, do: "second", else: "seconds"
          :minute -> if parser.offset == 1, do: "minute", else: "minutes"  
          :hour -> if parser.offset == 1, do: "hour", else: "hours"
          :day -> if parser.offset == 1, do: "day", else: "days"
          :week -> if parser.offset == 1, do: "week", else: "weeks"
          :month -> if parser.offset == 1, do: "month", else: "months"
          :year -> if parser.offset == 1, do: "year", else: "years"
          _ -> "#{parser.unit}"
        end
        
        "#{parser.offset} #{unit_name}"
      else
        # Fallback for old format
        case granularity do
          "minute" -> "1 minute"
          "hour" -> "1 hour" 
          "day" -> "1 day"
          "week" -> "1 week"
          "month" -> "1 month"
          "year" -> "1 year"
          _ -> granularity
        end
      end
    rescue
      _ -> granularity
    end
  end

  defp render_granularity_button_group(assigns) do
    ~H"""
    <div class="relative">
      <label class="absolute -top-2 left-2 inline-block bg-white dark:bg-slate-800 px-1 text-xs font-medium text-gray-900 dark:text-white z-10">
        Granularity
      </label>
      <div class="inline-flex rounded-md shadow-sm border border-gray-300 dark:border-slate-600 focus-within:border-teal-500 focus-within:ring-1 focus-within:ring-teal-500" role="group">
        <%= for {granularity, index} <- Enum.with_index(@available_granularities) do %>
          <% position = cond do
            length(@available_granularities) == 1 -> :only
            index == 0 -> :first
            index == length(@available_granularities) - 1 -> :last
            true -> :middle
          end %>
          <button
            type="button"
            phx-target={@myself}
            phx-click="select_granularity"
            phx-value-granularity={granularity}
            data-tooltip={granularity_display_name(granularity)}
            class={[
              "relative inline-flex items-center px-3 py-2 text-sm font-medium focus:z-10 focus:outline-none h-9",
              case position do
                :only -> "rounded-md"
                :first -> "rounded-l-md"
                :middle -> ""
                :last -> "rounded-r-md"
              end,
              if(@granularity == granularity,
                do: "bg-white dark:bg-slate-700 text-teal-500 dark:text-teal-400 border-b-2 border-b-teal-500 font-semibold hover:shadow-[inset_0_-8px_16px_-8px_rgba(20,184,166,0.2)]",
                else: "bg-white dark:bg-slate-700 text-gray-700 dark:text-slate-300 border-b-2 border-b-transparent hover:border-b-gray-300 dark:hover:border-b-slate-400 hover:shadow-[inset_0_-8px_16px_-8px_rgba(107,114,128,0.15)] dark:hover:shadow-[inset_0_-8px_16px_-8px_rgba(148,163,184,0.15)]"
              ),
              case position do
                :first -> ""
                :only -> ""
                _ -> "border-l border-gray-300 dark:border-slate-600"
              end
            ]}
          >
            <%= granularity %>
          </button>
        <% end %>
      </div>
    </div>
    """
  end
  
end
