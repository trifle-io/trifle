defmodule TrifleApp.DesignSystem.ChartColors do
  @moduledoc """
  Official chart color palettes for Trifle Analytics.
  """

  @default_palette [
    # Teal-600 (primary)
    "#14b8a6",
    # Amber-500
    "#f59e0b",
    # Red-500
    "#ef4444",
    # Violet-500
    "#8b5cf6",
    # Cyan-500
    "#06b6d4",
    # Emerald-500
    "#10b981",
    # Orange-500
    "#f97316",
    # Pink-500
    "#ec4899",
    # Blue-500
    "#3b82f6",
    # Lime-500
    "#84cc16",
    # Rose-500
    "#f43f5e",
    # Indigo-500
    "#6366f1"
  ]

  @palettes %{
    "default" => @default_palette,
    "purple" => ["#C4B5FD", "#A78BFA", "#8B5CF6", "#7C3AED", "#6D28D9", "#5B21B6", "#4C1D95"],
    "cool" => ["#BFDBFE", "#93C5FD", "#60A5FA", "#38BDF8", "#0EA5E9", "#0284C7", "#0369A1"],
    "green" => ["#BBF7D0", "#86EFAC", "#4ADE80", "#22C55E", "#16A34A", "#15803D", "#166534"],
    "warm" => ["#FDE68A", "#FCD34D", "#FBBF24", "#F59E0B", "#F97316", "#EF4444", "#DC2626"]
  }

  @palette_labels %{
    "default" => "Default",
    "purple" => "Purple",
    "cool" => "Cool",
    "green" => "Green",
    "warm" => "Warm"
  }
  @palette_order ["default", "purple", "cool", "green", "warm"]

  @default_palette_id "default"

  @doc """
  Returns the complete default color palette.

  ## Examples
      
      iex> TrifleApp.DesignSystem.ChartColors.palette()
      ["#14b8a6", "#f59e0b", "#ef4444", "#8b5cf6", "#06b6d4", "#10b981", 
       "#f97316", "#ec4899", "#3b82f6", "#84cc16", "#f43f5e", "#6366f1"]
  """
  def palette, do: @default_palette

  @doc """
  Returns all named palettes keyed by palette id.
  """
  def palettes, do: @palettes

  @doc """
  Returns palette metadata for selector UIs.
  """
  def palette_options do
    @palette_order
    |> Enum.map(fn id ->
      %{
        id: id,
        label: Map.get(@palette_labels, id, id),
        colors: Map.get(@palettes, id, [])
      }
    end)
  end

  @doc """
  Returns palette colors for the given palette id.
  Falls back to the default palette when not found.
  """
  def palette_by_id(palette_id) do
    palette_id
    |> normalize_palette_id()
    |> then(&Map.get(@palettes, &1, @default_palette))
  end

  @doc """
  Returns the color at a specific index (0-based) in the default palette.

  ## Examples

      iex> TrifleApp.DesignSystem.ChartColors.color_at(0)
      "#14b8a6"
      
      iex> TrifleApp.DesignSystem.ChartColors.color_at(1)
      "#f59e0b"
  """
  def color_at(index) when index >= 0 do
    Enum.at(@default_palette, index)
  end

  @doc """
  Returns the color at a specific index (0-based) in a named palette.
  """
  def color_at(palette_id, index) when index >= 0 do
    palette_id
    |> palette_by_id()
    |> Enum.at(index)
  end

  @doc """
  Returns a color for the given index in the default palette with automatic cycling.
  If the index exceeds the palette size, it cycles back to the beginning.

  ## Examples

      iex> TrifleApp.DesignSystem.ChartColors.color_for(0)
      "#14b8a6"
      
      iex> TrifleApp.DesignSystem.ChartColors.color_for(12)
      "#14b8a6"  # Cycles back to first color
      
      iex> TrifleApp.DesignSystem.ChartColors.color_for(13)
      "#f59e0b"  # Second color
  """
  def color_for(index) when index >= 0 do
    palette_size = length(@default_palette)
    color_index = rem(index, palette_size)
    Enum.at(@default_palette, color_index)
  end

  @doc """
  Returns a color for the given index in a named palette with automatic cycling.
  """
  def color_for(palette_id, index) when index >= 0 do
    palette = palette_by_id(palette_id)
    palette_size = length(palette)

    case palette_size do
      0 -> hd(@default_palette)
      _ -> Enum.at(palette, rem(index, palette_size))
    end
  end

  @doc """
  Returns the number of colors in the default palette.

  ## Examples

      iex> TrifleApp.DesignSystem.ChartColors.count()
      12
  """
  def count, do: length(@default_palette)

  @doc """
  Returns the number of colors in a named palette.
  """
  def count(palette_id) do
    palette_id
    |> palette_by_id()
    |> length()
  end

  @doc """
  Returns colors for a list of items, cycling through the default palette as needed.

  ## Examples

      iex> TrifleApp.DesignSystem.ChartColors.colors_for(["key1", "key2", "key3"])
      [{"key1", "#14b8a6"}, {"key2", "#f59e0b"}, {"key3", "#ef4444"}]
  """
  def colors_for(items) when is_list(items) do
    items
    |> Enum.with_index()
    |> Enum.map(fn {item, index} -> {item, color_for(index)} end)
  end

  @doc """
  Returns the palette as a JSON-encoded string for JavaScript consumption.

  ## Examples

      iex> TrifleApp.DesignSystem.ChartColors.json_palette()
      "[\"#14b8a6\",\"#f59e0b\",\"#ef4444\",\"#8b5cf6\",\"#06b6d4\",\"#10b981\",\"#f97316\",\"#ec4899\",\"#3b82f6\",\"#84cc16\",\"#f43f5e\",\"#6366f1\"]"
  """
  def json_palette do
    Jason.encode!(@default_palette)
  end

  @doc """
  Returns all palettes as a JSON-encoded map for JavaScript consumption.
  """
  def json_palettes do
    Jason.encode!(@palettes)
  end

  @doc """
  Returns the primary color (first color in the default palette).

  ## Examples

      iex> TrifleApp.DesignSystem.ChartColors.primary()
      "#14b8a6"
  """
  def primary, do: hd(@default_palette)

  defp normalize_palette_id(palette_id) do
    palette_id
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> @default_palette_id
      id -> id
    end
  end
end
