defmodule TrifleApp.Components.DashboardWidgets.TableTest do
  use ExUnit.Case, async: true

  alias TrifleApp.Components.DataTable
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

  test "table expression rows align with naive timestamps and compute derived values" do
    at = [~N[2024-01-01 00:00:00], ~N[2024-01-02 00:00:00]]

    values = [
      %{"orders" => 10, "revenue" => 200},
      %{"orders" => 20, "revenue" => 600}
    ]

    series = %Trifle.Stats.Series{
      series: %{
        at: at,
        values: values,
        granularity: "1d"
      }
    }

    widget = %{
      "id" => "table-expression",
      "type" => "table",
      "series" => [
        %{
          "kind" => "path",
          "path" => "orders",
          "expression" => "",
          "label" => "",
          "visible" => true,
          "color_selector" => "default.*"
        },
        %{
          "kind" => "path",
          "path" => "revenue",
          "expression" => "",
          "label" => "",
          "visible" => true,
          "color_selector" => "default.*"
        },
        %{
          "kind" => "expression",
          "path" => "",
          "expression" => "b / a",
          "label" => "avg",
          "visible" => true,
          "color_selector" => "warm.*"
        }
      ]
    }

    %{rows: rows, columns: columns, values: table_values} = Table.dataset(series, widget)
    avg_row = Enum.find(rows, &(&1.display_path == "avg"))

    assert avg_row
    assert Enum.map(columns, & &1.at) == [~U[2024-01-02 00:00:00Z], ~U[2024-01-01 00:00:00Z]]
    assert table_values[{avg_row.path, ~U[2024-01-01 00:00:00Z]}] == 20.0
    assert table_values[{avg_row.path, ~U[2024-01-02 00:00:00Z]}] == 30.0
  end

  test "aggrid payload keeps missing values blank" do
    at = ~U[2024-01-01 00:00:00Z]

    payload =
      DataTable.to_aggrid_payload(%{
        id: "table-empty",
        rows: [%{path: "avg", display_path: "avg", index: 1}],
        columns: [%{at: at, index: 1}],
        values: %{},
        granularity: "1d",
        empty_message: "No data available yet."
      })

    assert [%{path: "avg", display_path: "avg", values: [nil], path_html: path_html}] =
             payload.rows

    assert path_html =~ "avg"
  end
end
