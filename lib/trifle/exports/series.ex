defmodule Trifle.Exports.Series do
  @moduledoc """
  Helpers for exporting time-series data fetched via `Trifle.Stats.Source`.

  Provides a small wrapper around `Source.fetch_series/6` plus CSV/JSON
  encoding so dashboards, Explore, monitors, and scheduled jobs can share the
  same implementation.
  """

  alias Trifle.Stats.Source
  alias Trifle.Stats.Tabler
  alias Trifle.Stats.Series, as: StatsSeries

  @type series_map :: map()

  defmodule Result do
    @enforce_keys [:series, :raw]
    defstruct [:series, :raw]
  end

  @type result :: %Result{series: series_map(), raw: map()}

  @doc """
  Fetches export-ready series data from a `Source`.

  Returns `{:ok, %Result{}}` when data is present, `{:error, :no_data}` when the
  series lacks timeline points, or any error returned by `Source.fetch_series/6`.
  """
  @spec fetch(Source.t(), String.t() | nil, DateTime.t(), DateTime.t(), String.t(), Keyword.t()) ::
          {:ok, result()} | {:error, :no_data | term()}
  def fetch(%Source{} = source, key, from, to, granularity, opts \\ []) do
    opts = Keyword.put_new(opts, :progress_callback, nil)

    case Source.fetch_series(source, key, from, to, granularity, opts) do
      {:ok, raw} ->
        series = normalize_series(raw.series)

        if has_data?(series) do
          {:ok, %Result{series: series, raw: raw}}
        else
          {:error, :no_data}
        end

      other ->
        other
    end
  end

  @doc """
  Returns `true` when the series has at least one timeline entry.
  """
  @spec has_data?(series_map() | result() | nil) :: boolean()
  def has_data?(%Result{} = result), do: has_data?(result.series)
  def has_data?(%StatsSeries{} = series), do: has_data?(series.series)

  def has_data?(series) when is_map(series) do
    case Map.get(series, :at) do
      list when is_list(list) -> Enum.any?(list)
      _ -> false
    end
  end

  def has_data?(_), do: false

  @doc """
  Encodes the provided series (or `%Result{}`) into CSV.
  """
  @spec to_csv(series_map() | result()) :: String.t()
  def to_csv(series_or_result) do
    series = extract_series(series_or_result)
    table = Tabler.tabulize(series)
    at = Enum.reverse(table[:at] || [])
    paths = table[:paths] || []
    values_map = table[:values] || %{}
    header = ["Path" | Enum.map(at, &DateTime.to_iso8601/1)]

    rows =
      Enum.map(paths, fn path ->
        [path | Enum.map(at, fn t -> Map.get(values_map, {path, t}) || 0 end)]
      end)

    [header | rows]
    |> Enum.map(fn cols -> cols |> Enum.map(&csv_escape/1) |> Enum.join(",") end)
    |> Enum.join("\n")
  end

  @doc """
  Encodes the provided series (or `%Result{}`) into JSON.
  """
  @spec to_json(series_map() | result()) :: String.t()
  def to_json(series_or_result) do
    series = extract_series(series_or_result)
    at = (series[:at] || []) |> Enum.map(&DateTime.to_iso8601/1)
    values = series[:values] || []

    Jason.encode!(%{at: at, values: values})
  end

  @doc """
  Extracts the normalised series map from either a `%Result{}` or a raw value.
  """
  @spec extract_series(series_map() | result() | StatsSeries.t()) :: series_map()
  def extract_series(%Result{series: series}), do: series
  def extract_series(%StatsSeries{} = series), do: normalize_series(series)
  def extract_series(series) when is_map(series), do: normalize_series(series)
  def extract_series(_), do: %{}

  @doc """
  Normalises different shapes (`%StatsSeries{}`, plain map, etc) into a map.
  """
  @spec normalize_series(series_map() | StatsSeries.t() | nil) :: series_map()
  def normalize_series(%StatsSeries{series: inner}) when is_map(inner),
    do: normalize_series(inner)

  def normalize_series(%{} = series_map), do: series_map
  def normalize_series(_), do: %{}

  defp csv_escape(v) when is_binary(v) do
    escaped = String.replace(v, "\"", "\"\"")
    "\"" <> escaped <> "\""
  end

  defp csv_escape(nil), do: ""
  defp csv_escape(v) when is_integer(v) or is_float(v), do: to_string(v)
  defp csv_escape(v), do: csv_escape(to_string(v))
end
