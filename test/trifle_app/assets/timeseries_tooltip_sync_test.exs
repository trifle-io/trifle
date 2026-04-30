defmodule TrifleApp.Assets.TimeseriesTooltipSyncTest do
  use ExUnit.Case, async: true

  @source_path "assets/js/widgets/dashboard_runtime/dashboard_grid_renderers/timeseries.js"

  test "linked tooltip sync skips charts that have no value at the hovered timestamp before updating the axis pointer" do
    source = File.read!(@source_path)

    assert source =~ "const idx = this._nearest_ts_index(chart, value);"
    assert source =~ "if (idx == null || !this._ts_index_has_value(chart, idx)) return;"

    idx_pos =
      :binary.match(source, "const idx = this._nearest_ts_index(chart, value);") |> elem(0)

    guard_pos =
      :binary.match(source, "if (idx == null || !this._ts_index_has_value(chart, idx)) return;")
      |> elem(0)

    axis_pos =
      :binary.match(
        source,
        "chart.dispatchAction({ type: 'updateAxisPointer', xAxisIndex: 0, value });"
      )
      |> elem(0)

    assert idx_pos < guard_pos
    assert guard_pos < axis_pos
  end
end
