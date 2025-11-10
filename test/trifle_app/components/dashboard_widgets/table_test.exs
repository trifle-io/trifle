defmodule TrifleApp.Components.DashboardWidgets.TableTest do
  use ExUnit.Case, async: true

  alias TrifleApp.Components.DashboardWidgets.Table

  test "dataset filters by configured paths and trims prefix" do
    at = [~U[2024-01-01 00:00:00Z]]

    values = [
      %{
        "metrics" => %{
          "table" => %{"payments" => %{"credit" => 5, "digital" => 7}},
          "other" => 1
        }
      }
    ]

    series = %Trifle.Stats.Series{
      series: %{
        at: at,
        values: values,
        granularity: "1d"
      }
    }

    widget = %{
      "id" => "table-1",
      "type" => "table",
      "paths" => ["metrics.table"]
    }

    [%{rows: rows, columns: columns}] = Table.datasets(series, [widget])

    assert Enum.any?(rows, &(&1.display_path == "payments.credit"))
    assert Enum.any?(rows, &(&1.display_path == "payments.digital"))
    assert Enum.all?(columns, &match?(%{at: _}, &1))
  end
end
