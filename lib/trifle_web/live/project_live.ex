defmodule TrifleWeb.ProjectLive do
  use TrifleWeb, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.Project

  require IEx

  def mount(params, _session, socket) do
    project = Organizations.get_project!(params["id"])

    socket = socket
    |> assign(page_title: "Projects |> #{project.name} |> Explore")
    |> assign(project: project)
    |> assign(stats: nil)
    |> assign(timeline: "")

    {:ok, socket}
  end

  def parse_date(date, time_zone) do
    case DateTime.from_iso8601(date) do
      {:ok, parsed, _} -> {:ok, parsed}
      {:error, _} -> DateTime.now(time_zone, Tzdata.TimeZoneDatabase)
    end
  end

  def handle_event("fetch", params, socket) do
    range = params["range"]
    {:ok, from} = parse_date("#{params["from"]}:00Z", socket.assigns.project.time_zone)
    {:ok, to} = parse_date("#{params["to"]}:00Z", socket.assigns.project.time_zone)

    socket = socket
    |> assign(range: range, from: from, to: to)
    |> push_patch(to: ~p"/app/projects/#{socket.assigns.project.id}?#{[range: range, from: DateTime.to_string(from), to: DateTime.to_string(to), key: socket.assigns.key]}")

    {:noreply, socket}
  end


  def handle_params(params, session, socket) do
    range = params["range"] || "daily"
    {:ok, from} = parse_date((params["from"] || ""), socket.assigns.project.time_zone)
    {:ok, to} = parse_date((params["to"] || ""), socket.assigns.project.time_zone)
    project_stats = load_project_stats(socket.assigns.project, range, from, to)
    keys_sum = reduce_stats(project_stats[:values])
    timeline = series_from(project_stats, ["keys", params["key"]])
    key_stats = load_project_key_stats(socket.assigns.project, params["key"], range, from, to)
    {:ok, key_tabulized, key_seriesized} = process_project_key_stats(key_stats)
    # IEx.pry
    socket = socket
    |> assign(range: range, from: from, to: to)
    |> assign(key: params["key"])
    |> assign(keys: keys_sum)
    |> assign(timeline: Jason.encode!(timeline["keys.#{params["key"]}"]))
    |> assign(stats: key_tabulized)
    |> assign(form: to_form(%{}))

    {:noreply, socket}
  end

  def load_project_stats(project, range, from, to) do
    intervals = %{hourly: :hour, daily: :day, weekly: :week, monthly: :month, quarterly: :quarter, yearly: :year}
    range = intervals[String.to_atom(range)]

    Trifle.Stats.values("__system__keys__", from, to, range, Project.stats_config(project))
  end

  def reduce_stats(values) do
    Enum.reduce(values, [], fn(data, acc) -> [data["keys"] | acc] end)
    |> Enum.reduce(%{}, fn(data, acc) -> Trifle.Stats.Packer.deep_sum(acc, data) end)
  end

  def series_from(%{at: at, values: values} = stats, path) when is_list(path) do
    key = Enum.join(path, ".")
    Enum.with_index(at)
    |> Enum.reduce(%{}, fn({a, i}, acc) ->
      v = get_in(Enum.at(values, i), path)
      acc = Map.put(acc, key, [[DateTime.to_unix(a) * 1000, (v || 0)] | (acc[key] || [])])
    end)
  end

  def load_project_key_stats(project, key, range, from, to) when is_nil(key), do: nil
  def load_project_key_stats(project, key, range, from, to) when is_binary(key) and byte_size(key) == 0, do: nil

  def load_project_key_stats(project, key, range, from, to) do
    intervals = %{hourly: :hour, daily: :day, weekly: :week, monthly: :month, quarterly: :quarter, yearly: :year}
    range = intervals[String.to_atom(range)]

    Trifle.Stats.values(key, from, to, range, Project.stats_config(project))
  end

  def process_project_key_stats(stats) when is_nil(stats), do: {:ok, nil, nil}

  def process_project_key_stats(stats) do
    {
      :ok,
      Trifle.Stats.Tabler.tabulize(stats),
      Trifle.Stats.Tabler.seriesize(stats)
    }
  end

  def render(assigns) do
    ~H"""
    <div class="">
      <div class="sm:p-4">
        <div class="border-b border-gray-200">
          <nav class="-mb-px space-x-8" aria-label="Tabs">
            <.link navigate={~p"/app/projects/#{@project.id}"} class="border-teal-500 text-teal-600 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium" aria-current="page">
              <svg class="text-teal-400 group-hover:text-teal-500 -ml-0.5 mr-2 h-5 w-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3.375 19.5h17.25m-17.25 0a1.125 1.125 0 01-1.125-1.125M3.375 19.5h7.5c.621 0 1.125-.504 1.125-1.125m-9.75 0V5.625m0 12.75v-1.5c0-.621.504-1.125 1.125-1.125m18.375 2.625V5.625m0 12.75c0 .621-.504 1.125-1.125 1.125m1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125m0 3.75h-7.5A1.125 1.125 0 0112 18.375m9.75-12.75c0-.621-.504-1.125-1.125-1.125H3.375c-.621 0-1.125.504-1.125 1.125m19.5 0v1.5c0 .621-.504 1.125-1.125 1.125M2.25 5.625v1.5c0 .621.504 1.125 1.125 1.125m0 0h17.25m-17.25 0h7.5c.621 0 1.125.504 1.125 1.125M3.375 8.25c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125m17.25-3.75h-7.5c-.621 0-1.125.504-1.125 1.125m8.625-1.125c.621 0 1.125.504 1.125 1.125v1.5c0 .621-.504 1.125-1.125 1.125m-17.25 0h7.5m-7.5 0c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125M12 10.875v-1.5m0 1.5c0 .621-.504 1.125-1.125 1.125M12 10.875c0 .621.504 1.125 1.125 1.125m-2.25 0c.621 0 1.125.504 1.125 1.125M13.125 12h7.5m-7.5 0c-.621 0-1.125.504-1.125 1.125M20.625 12c.621 0 1.125.504 1.125 1.125v1.5c0 .621-.504 1.125-1.125 1.125m-17.25 0h7.5M12 14.625v-1.5m0 1.5c0 .621-.504 1.125-1.125 1.125M12 14.625c0 .621.504 1.125 1.125 1.125m-2.25 0c.621 0 1.125.504 1.125 1.125m0 1.5v-1.5m0 0c0-.621.504-1.125 1.125-1.125m0 0h7.5" />
              </svg>
              <span class="hidden sm:block">Explore</span>
            </.link>
            <.link navigate={~p"/app/projects/#{@project.id}/transponders"} class="border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium">
              <svg class="text-gray-400 group-hover:text-gray-500 -ml-0.5 mr-2 h-5 w-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                <path stroke-linecap="round" stroke-linejoin="round" d="M21 7.5l-2.25-1.313M21 7.5v2.25m0-2.25l-2.25 1.313M3 7.5l2.25-1.313M3 7.5l2.25 1.313M3 7.5v2.25m9 3l2.25-1.313M12 12.75l-2.25-1.313M12 12.75V15m0 6.75l2.25-1.313M12 21.75V19.5m0 2.25l-2.25-1.313m0-16.875L12 2.25l2.25 1.313M21 14.25v2.25l-2.25 1.313m-13.5 0L3 16.5v-2.25" />
              </svg>
              <span class="hidden sm:block">Transponders</span>
            </.link>
            <.link navigate={~p"/app/projects/#{@project.id}/tokens"} class="float-right border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium">
              <svg class="text-gray-400 group-hover:text-gray-500 -ml-0.5 mr-2 h-5 w-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 5.25a3 3 0 013 3m3 0a6 6 0 01-7.029 5.912c-.563-.097-1.159.026-1.563.43L10.5 17.25H8.25v2.25H6v2.25H2.25v-2.818c0-.597.237-1.17.659-1.591l6.499-6.499c.404-.404.527-1 .43-1.563A6 6 0 1121.75 8.25z" />
              </svg>
              <span class="hidden sm:block">Tokens</span>
            </.link>
            <.link navigate={~p"/app/projects/#{@project.id}/settings"} class="float-right border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium">
              <svg class="text-gray-400 group-hover:text-gray-500 -ml-0.5 mr-2 h-5 w-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                <path stroke-linecap="round" stroke-linejoin="round" d="M11.42 15.17L17.25 21A2.652 2.652 0 0021 17.25l-5.877-5.877M11.42 15.17l2.496-3.03c.317-.384.74-.626 1.208-.766M11.42 15.17l-4.655 5.653a2.548 2.548 0 11-3.586-3.586l6.837-5.63m5.108-.233c.55-.164 1.163-.188 1.743-.14a4.5 4.5 0 004.486-6.336l-3.276 3.277a3.004 3.004 0 01-2.25-2.25l3.276-3.276a4.5 4.5 0 00-6.336 4.486c.091 1.076-.071 2.264-.904 2.95l-.102.085m-1.745 1.437L5.909 7.5H4.5L2.25 3.75l1.5-1.5L7.5 4.5v1.409l4.26 4.26m-1.745 1.437l1.745-1.437m6.615 8.206L15.75 15.75M4.867 19.125h.008v.008h-.008v-.008z" />
              </svg>
              <span class="hidden sm:block">Settings</span>
            </.link>
          </nav>
        </div>
      </div>
    </div>

    <div class="min-h-full flex-col h-full">

        <div class="flex-1 xl:flex">
          <div class="xl:w-96 xl:shrink-0">
            <!-- Left column area -->

            <div class="text-lg font-semibold leading-6 text-gray-900">Timeframe</div>
            <div class="text-2xl font-bold font-mono text-center text-gray-600 mt-5 mr-4">
              <.form for={@form} phx-submit="fetch" class="flex h-full flex-col overflow-y-scroll bg-white rounded-lg shadow py-3.5 pl-4 pr-3 sm:pl-3">
                <div class="relative mt-1">
                  <.filter_input field={@form[:from]} value={@from} name="from" id="filter_from" type="datetime-local" label="From" />
                </div>
                <div class="relative mt-5">
                  <.filter_input field={@form[:to]} name="to" value={@to} id="filter_to" type="datetime-local" label="To" />
                </div>
                <div class="relative mt-5">
                  <.filter_input field={@form[:range]} value={@range} type="select" label="Range" options={[{"Hourly", :hourly}, {"Daily", :daily}, {"Weekly", :weekly}, {"Monthly", :monthly}, {"Quarterly", :quarterly}, {"Yearly", :yearly}]} />
                </div>

                <.button class="mt-5 w-full inline-flex justify-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600">
                  <.icon name="hero-funnel" />
                </.button>
              </.form>
            </div>

            <div class="text-lg font-semibold leading-6 text-gray-900 mt-5">Keys</div>
            <div class="bg-white rounded-lg shadow mr-4 mt-5">
              <div class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 sm:pl-3 border-b">
                <span class="inline-flex items-center rounded-md bg-teal-100 px-2 py-1 text-xs font-medium text-teal-600 ring-1 ring-inset ring-gray-500/10 float-right">Events</span>
                Key
              </div>
              <ul role="list" class="divide-y divide-gray-100">
                <%= for {key, count} <- @keys do %>
                  <li class={if @key == key, do: "relative py-5 bg-teal-50 hover:bg-gray-50", else: "relative py-5 bg-white hover:bg-gray-50"}>
                    <div class="px-4 sm:px-6 lg:px-8">
                      <div class="mx-auto flex max-w-4xl justify-between gap-x-6">
                        <div class="flex gap-x-4">
                          <div class="min-w-0 flex-auto">
                            <p class={if @key == key, do: "text-sm font-semibold font-mono leading-6 text-teal-700", else: "text-sm font-semibold font-mono leading-6 text-gray-900"}>
                              <.link navigate={~p"/app/projects/#{@project.id}?#{[range: @range, from: DateTime.to_string(@from), to: DateTime.to_string(@to), key: key]}"}>
                                <span class="absolute inset-x-0 -top-px bottom-0"></span>
                                <%= key %>
                              </.link>
                            </p>
                          </div>
                        </div>
                        <div class="flex items-center gap-x-4">
                          <span class="inline-flex items-center rounded-md bg-teal-100 px-2 py-1 text-xs font-medium text-teal-600 ring-1 ring-inset ring-gray-500/10 float-right"><%= count %></span>
                          <svg class="h-5 w-5 flex-none text-gray-400" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                            <path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z" clip-rule="evenodd" />
                          </svg>
                        </div>
                     </div>
                    </div>
                  </li>
                <% end %>
              </ul>
            </div>
            &nbsp
          </div>

          <div class="xl:flex-1 overflow-x-auto overflow-hidden">
            <%= if @stats do %>
              <div class="text-lg font-semibold leading-6 text-gray-900">Events</div>
              <div id="timeline-hook" phx-hook="ProjectTimeline" data-events={@timeline} data-key={@key} class=""></div>
              <div id="timeline-chart-wrapper" phx-update="ignore" class="mt-5">
                <div id="timeline-chart" class="bg-white rounded-lg shadow"></div>
              </div>

              <div class="text-lg font-semibold leading-6 text-gray-900 mt-5">Data</div>


    <nav class="flex space-x-4 mt-5" aria-label="Tabs">
      <!-- Current: "bg-gray-200 text-gray-800", Default: "text-gray-600 hover:text-gray-800" -->
      <a href="#" class="text-gray-600 hover:text-gray-800 rounded-md px-3 py-2 text-sm font-medium">Charts</a>
      <a href="#" class="bg-gray-200 text-gray-800 rounded-md px-3 py-2 text-sm font-medium" aria-current="page">Table</a>
    </nav>




              <div class="overflow-x-auto overflow-hidden bg-white rounded-lg shadow mt-5">
                <table class="min-w-full divide-y divide-gray-300 overflow-auto">
                  <thead>
                    <tr>
                      <th scope="col" class="top-0 left-0 sticky bg-white whitespace-nowrap py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 pl-4">Path</th>
                      <%= for at <- Enum.reverse(@stats[:at]) do %>
                        <th scope="col" class="top-0 sticky whitespace-nowrap px-2 py-3.5 text-left text-xs font-mono font-semibold text-teal-700"><%= at %></th>
                      <% end %>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-gray-200 bg-white">
                    <%= for path <- @stats[:paths] do %>
                      <tr>
                        <td class="left-0 sticky bg-white whitespace-nowrap py-2 pl-4 pr-3 text-sm font-mono pl-4">
                          <span class="text-teal-500"><%= path %></span>
                        </td>
                        <%= for at <- Enum.reverse(@stats[:at]) do %>
                          <% value = @stats[:values][{path, at}] %>
                          <%= if value do %>
                            <td class="whitespace-nowrap px-2 py-2 text-sm font-medium text-gray-900"><%= value %></td>
                          <% else %>
                            <td class="whitespace-nowrap px-2 py-2 text-sm font-medium text-gray-300">0</td>
                          <% end %>
                        <% end %>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% else %>
              &larr; Select Key there.
            <% end %>
        </div>
      </div>
    </div>

    """
  end
 end
