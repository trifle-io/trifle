defmodule TrifleApp.Components.DashboardWidgets.SharedParse do
  @moduledoc false

  def parse_numeric_bucket(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  def parse_numeric_bucket(value) when is_integer(value), do: value * 1.0
  def parse_numeric_bucket(value) when is_float(value), do: value

  def parse_numeric_bucket(value) when is_binary(value) do
    trimmed = String.trim(value)

    case trimmed do
      "" ->
        nil

      _ ->
        parse_numeric_string(trimmed)
    end
  end

  def parse_numeric_bucket(_), do: nil

  defp parse_numeric_string(string) do
    case Float.parse(string) do
      {value, ""} ->
        value

      _ ->
        case Integer.parse(string) do
          {int, ""} -> int * 1.0
          _ -> nil
        end
    end
  rescue
    ArgumentError ->
      nil
  end
end
