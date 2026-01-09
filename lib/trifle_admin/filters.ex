defmodule TrifleAdmin.Filters do
  @moduledoc false

  def filter_records(records, query, field_fun) when is_list(records) do
    normalized_query =
      query
      |> Kernel.||("")
      |> to_string()
      |> String.trim()
      |> String.downcase()

    if normalized_query == "" do
      records
    else
      Enum.filter(records, fn record ->
        record
        |> field_fun.()
        |> Enum.filter(&present?/1)
        |> Enum.map(&to_string/1)
        |> Enum.any?(fn value ->
          value
          |> String.downcase()
          |> String.contains?(normalized_query)
        end)
      end)
    end
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true
end
