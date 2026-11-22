defmodule TrifleApp.PathSuggestions do
  @moduledoc """
  Builds metric path autocomplete options from loaded or sampled series data.
  """

  alias Phoenix.HTML
  alias Trifle.Stats.Source
  alias Trifle.Stats.Nocturnal.Parser
  alias Trifle.Stats.Tabler
  alias TrifleApp.DesignSystem.PathColors
  alias TrifleApp.ExploreCore

  @one_week_seconds 7 * 24 * 60 * 60

  @type sample_meta :: %{
          optional(:granularity) => String.t(),
          optional(:from) => DateTime.t(),
          optional(:to) => DateTime.t()
        }

  @spec sample_options(Source.t() | nil, String.t() | nil, keyword()) ::
          {:ok, %{options: list(), meta: sample_meta()}} | {:error, term()}
  def sample_options(source, key, opts \\ [])

  def sample_options(nil, _key, _opts), do: {:error, :missing_source}

  def sample_options(_source, key, _opts) when key in [nil, ""], do: {:error, :missing_key}

  def sample_options(%Source{} = source, key, opts) do
    time_zone = opts[:time_zone] || Source.time_zone(source)

    with {:ok, granularity} <- select_granularity(source, opts),
         {:ok, {from, to}} <-
           timeframe_window(granularity, Keyword.put(opts, :time_zone, time_zone)),
         {:ok, result} <-
           Source.fetch_series(
             source,
             key,
             from,
             to,
             granularity,
             Keyword.merge([transponders: :none], opts[:fetch_opts] || [])
           ) do
      {:ok,
       %{
         options: options_for_series(result.series),
         meta: %{
           granularity: granularity,
           from: from,
           to: to
         }
       }}
    else
      {:error, reason} -> {:error, reason}
      {:invalid_granularity, value} -> {:error, {:invalid_granularity, value}}
      {:no_granularity, _} = error -> {:error, error}
      other -> {:error, other}
    end
  end

  @doc """
  Picks the best granularity for sampling based on the source's advertised granularities.
  Prefers exactly 1 week, otherwise chooses the smallest granularity >= 1 week.
  Falls back to the largest available granularity when nothing exceeds 1 week.
  """
  @spec select_granularity(Source.t(), keyword()) ::
          {:ok, String.t()} | {:invalid_granularity, String.t()} | {:error, term()}
  def select_granularity(%Source{} = source, opts \\ []) do
    available =
      opts[:available_granularities] ||
        (Source.available_granularities(source) || [])

    parsed =
      available
      |> Enum.map(&to_string/1)
      |> Enum.uniq()
      |> Enum.map(&parse_granularity/1)
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, value} -> value end)

    cond do
      parsed == [] ->
        {:error, {:no_granularity, available}}

      Enum.any?(parsed, &(&1.string == "1w")) ->
        {:ok, "1w"}

      match =
          parsed
          |> Enum.filter(&(&1.duration >= @one_week_seconds))
          |> Enum.min_by(& &1.duration, fn -> nil end) ->
        {:ok, match.string}

      true ->
        parsed
        |> Enum.max_by(& &1.duration)
        |> then(&{:ok, &1.string})
    end
  end

  @doc """
  Calculates a simple window that spans one segment of the provided granularity.
  """
  @spec timeframe_window(String.t(), keyword()) ::
          {:ok, {DateTime.t(), DateTime.t()}} | {:invalid_granularity, String.t()}
  def timeframe_window(granularity, opts \\ []) do
    case parse_granularity(granularity) do
      {:ok, %{duration: duration}} ->
        base_now =
          opts[:now] ||
            DateTime.utc_now()

        to =
          case opts[:time_zone] do
            nil -> base_now
            tz -> DateTime.shift_zone!(base_now, tz)
          end

        from = DateTime.add(to, -duration, :second)
        {:ok, {from, to}}

      {:error, _} ->
        {:invalid_granularity, granularity}
    end
  end

  def options_for_series(series, transponder_info \\ %{})

  def options_for_series(%Trifle.Stats.Series{series: series_map}, transponder_info) do
    options_for_series(series_map, transponder_info)
  end

  def options_for_series(%{at: _, values: _} = series_map, transponder_info) do
    %{paths: paths} = Tabler.tabulize(series_map)
    path_colors = PathColors.build(paths)

    Enum.map(paths, fn path ->
      label =
        path
        |> ExploreCore.format_nested_path(paths, transponder_info, path_colors: path_colors)
        |> HTML.safe_to_string()

      segment_colors = path |> PathColors.parts(path_colors) |> Enum.map(& &1.color)

      %{"value" => path, "label" => label, "segment_colors" => segment_colors}
    end)
  end

  def options_for_series(_, _), do: []

  defp parse_granularity(value) do
    parser = Parser.new(value)

    if Parser.valid?(parser) do
      {:ok,
       %{
         string: value,
         duration: duration_in_seconds(parser.unit, parser.offset)
       }}
    else
      {:error, :invalid}
    end
  end

  defp duration_in_seconds(:second, offset), do: offset
  defp duration_in_seconds(:minute, offset), do: offset * 60
  defp duration_in_seconds(:hour, offset), do: offset * 60 * 60
  defp duration_in_seconds(:day, offset), do: offset * 24 * 60 * 60
  defp duration_in_seconds(:week, offset), do: offset * @one_week_seconds
  defp duration_in_seconds(:month, offset), do: offset * 30 * 24 * 60 * 60
  defp duration_in_seconds(:quarter, offset), do: offset * 90 * 24 * 60 * 60
  defp duration_in_seconds(:year, offset), do: offset * 365 * 24 * 60 * 60
  defp duration_in_seconds(_, offset), do: offset * 24 * 60 * 60
end
