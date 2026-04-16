defmodule TrifleApp.Components.FilterBarTest do
  use TrifleApp.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TrifleApp.Components.FilterBar

  defmodule HarnessLive do
    use TrifleApp, :live_view

    alias TrifleApp.Components.FilterBar

    @impl true
    def mount(_params, session, socket) do
      assigns =
        session
        |> Enum.into(%{}, fn {key, value} -> {String.to_atom(key), value} end)
        |> Map.put_new(:force_granularity_dropdown, false)

      {:ok, assign(socket, assigns), layout: false}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <.live_component
        module={FilterBar}
        id={@id}
        config={@config}
        from={@from}
        to={@to}
        granularity={@granularity}
        smart_timeframe_input={@smart_timeframe_input}
        use_fixed_display={@use_fixed_display}
        available_granularities={@available_granularities}
        show_controls={@show_controls}
        show_timeframe_dropdown={@show_timeframe_dropdown}
        show_granularity_dropdown={@show_granularity_dropdown}
        force_granularity_dropdown={@force_granularity_dropdown}
        sources={@sources}
        selected_source={@selected_source}
        source_locked={@source_locked}
        loading={@loading}
        loading_chunks={@loading_chunks}
        loading_progress={@loading_progress}
        transponding={@transponding}
      />
      """
    end
  end

  test "renders chunk loading status inside the filter bar", %{conn: conn} do
    {:ok, _view, html} =
      live_isolated(conn, HarnessLive,
        session:
          session(%{
            id: "filter-bar",
            config: %{time_zone: "UTC"},
            from: ~U[2024-01-01 00:00:00Z],
            to: ~U[2024-01-01 01:00:00Z],
            granularity: "1m",
            smart_timeframe_input: "1h",
            use_fixed_display: false,
            available_granularities: ["1m", "1h"],
            show_controls: true,
            show_timeframe_dropdown: false,
            show_granularity_dropdown: false,
            sources: [],
            selected_source: nil,
            source_locked: true,
            loading: true,
            loading_chunks: true,
            loading_progress: %{current: 2, total: 5},
            transponding: false
          })
      )

    assert html =~ "Scientificating piece 2 of 5..."
    assert html =~ "width: 40.0%"
    assert html =~ ~s(aria-busy="true")
  end

  test "renders transponding status without replacing the progress block markup", %{conn: conn} do
    {:ok, _view, html} =
      live_isolated(conn, HarnessLive,
        session:
          session(%{
            id: "filter-bar-transponding",
            config: %{time_zone: "UTC"},
            from: ~U[2024-01-01 00:00:00Z],
            to: ~U[2024-01-01 01:00:00Z],
            granularity: "1m",
            smart_timeframe_input: "1h",
            use_fixed_display: false,
            available_granularities: ["1m", "1h"],
            show_controls: true,
            show_timeframe_dropdown: false,
            show_granularity_dropdown: false,
            sources: [],
            selected_source: nil,
            source_locked: true,
            loading: true,
            loading_chunks: true,
            loading_progress: nil,
            transponding: true
          })
      )

    assert html =~ "Transponding data..."
    assert html =~ ~s(class="w-64 h-2")
  end

  test "does not clip open timeframe and granularity dropdowns", %{conn: conn} do
    {:ok, _view, html} =
      live_isolated(conn, HarnessLive,
        session:
          session(%{
            id: "filter-bar-dropdowns",
            config: %{time_zone: "UTC"},
            from: ~U[2024-01-01 00:00:00Z],
            to: ~U[2024-01-01 01:00:00Z],
            granularity: "1m",
            smart_timeframe_input: "1h",
            use_fixed_display: false,
            available_granularities: ["1m", "5m", "1h"],
            show_controls: true,
            show_timeframe_dropdown: true,
            show_granularity_dropdown: true,
            force_granularity_dropdown: true,
            sources: [],
            selected_source: nil,
            source_locked: true,
            loading: false,
            loading_chunks: false,
            loading_progress: nil,
            transponding: false
          })
      )

    assert html =~ "Quick Timeframes"
    assert html =~ "Granularity"
    refute html =~ "overflow-hidden rounded-2xl"
  end

  defp session(assigns) do
    Map.new(assigns, fn {key, value} -> {Atom.to_string(key), value} end)
  end
end
