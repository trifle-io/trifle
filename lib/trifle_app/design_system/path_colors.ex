defmodule TrifleApp.DesignSystem.PathColors do
  @moduledoc "Sibling-based segment colors shared by Stats and trace path labels."

  alias TrifleApp.DesignSystem.ChartColors

  @doc "Build a color lookup from all known paths, independently of visible row order."
  def build(paths, separator \\ ".") when separator in [".", "/"] do
    paths
    |> Enum.flat_map(fn path ->
      path |> segments(separator) |> Enum.scan([], fn part, prefix -> prefix ++ [part] end)
    end)
    |> Enum.uniq()
    |> Enum.group_by(&Enum.drop(&1, -1))
    |> Enum.flat_map(fn {_parent, siblings} ->
      siblings
      |> Enum.sort_by(&List.last/1)
      |> Enum.with_index(fn prefix, index -> {prefix, ChartColors.color_for(index)} end)
    end)
    |> Map.new()
  end

  @doc """
  Render a flat, escaped path with a separate colored span for each segment.
  Trace slashes inherit the preceding segment's color; Stats dots stay unchanged.
  """
  def html(path, colors, separator \\ ".") when separator in [".", "/"] do
    path
    |> parts(colors, separator)
    |> Enum.map(fn part ->
      ~s(<span style="color: #{escape(part.color)} !important">#{escape(part.label)}</span>)
    end)
    |> Enum.join(if separator == "/", do: "", else: separator)
    |> Phoenix.HTML.raw()
  end

  @doc "Colored labels and logical prefixes for building interactive path segments."
  def parts(path, colors, separator \\ ".") when separator in [".", "/"] do
    parts = segments(path, separator)
    count = length(parts)

    parts
    |> Enum.with_index(1)
    |> Enum.map_reduce([], fn {segment, index}, prefix ->
      prefix = prefix ++ [segment]
      color = Map.get(colors, prefix, ChartColors.color_for(0))
      suffix = if separator == "/" && index < count, do: "/", else: ""

      {%{label: segment <> suffix, color: color, segments: prefix}, prefix}
    end)
    |> elem(0)
  end

  defp segments(path, "."), do: Trifle.Stats.Path.segments(path)
  defp segments(path, "/"), do: String.split(path, "/")
  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
