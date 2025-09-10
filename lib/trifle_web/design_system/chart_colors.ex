defmodule TrifleWeb.DesignSystem.ChartColors do
  @moduledoc """
  Official chart color palette for Trifle Analytics.
  
  Provides a curated set of 12 vibrant colors based on Tailwind CSS 
  for consistent data visualization across charts and graphs.
  
  These colors ensure consistency across all chart instances in the application.
  """

  @official_palette [
    "#14b8a6",  # Teal-600 (primary)
    "#f59e0b",  # Amber-500
    "#ef4444",  # Red-500
    "#8b5cf6",  # Violet-500
    "#06b6d4",  # Cyan-500
    "#10b981",  # Emerald-500
    "#f97316",  # Orange-500
    "#ec4899",  # Pink-500
    "#3b82f6",  # Blue-500
    "#84cc16",  # Lime-500
    "#f43f5e",  # Rose-500
    "#6366f1"   # Indigo-500
  ]

  @doc """
  Returns the complete official color palette.
  
  ## Examples
      
      iex> TrifleWeb.DesignSystem.ChartColors.palette()
      ["#14b8a6", "#f59e0b", "#ef4444", "#8b5cf6", "#06b6d4", "#10b981", 
       "#f97316", "#ec4899", "#3b82f6", "#84cc16", "#f43f5e", "#6366f1"]
  """
  def palette, do: @official_palette

  @doc """
  Returns the color at a specific index (0-based).
  
  ## Examples
  
      iex> TrifleWeb.DesignSystem.ChartColors.color_at(0)
      "#14b8a6"
      
      iex> TrifleWeb.DesignSystem.ChartColors.color_at(1)
      "#f59e0b"
  """
  def color_at(index) when index >= 0 do
    Enum.at(@official_palette, index)
  end

  @doc """
  Returns a color for the given index with automatic cycling.
  If the index exceeds the palette size, it cycles back to the beginning.
  
  ## Examples
  
      iex> TrifleWeb.DesignSystem.ChartColors.color_for(0)
      "#14b8a6"
      
      iex> TrifleWeb.DesignSystem.ChartColors.color_for(12)
      "#14b8a6"  # Cycles back to first color
      
      iex> TrifleWeb.DesignSystem.ChartColors.color_for(13)
      "#f59e0b"  # Second color
  """
  def color_for(index) when index >= 0 do
    palette_size = length(@official_palette)
    color_index = rem(index, palette_size)
    Enum.at(@official_palette, color_index)
  end

  @doc """
  Returns the number of colors in the palette.
  
  ## Examples
  
      iex> TrifleWeb.DesignSystem.ChartColors.count()
      12
  """
  def count, do: length(@official_palette)

  @doc """
  Returns colors for a list of items, cycling through the palette as needed.
  
  ## Examples
  
      iex> TrifleWeb.DesignSystem.ChartColors.colors_for(["key1", "key2", "key3"])
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
  
      iex> TrifleWeb.DesignSystem.ChartColors.json_palette()
      "[\"#14b8a6\",\"#f59e0b\",\"#ef4444\",\"#8b5cf6\",\"#06b6d4\",\"#10b981\",\"#f97316\",\"#ec4899\",\"#3b82f6\",\"#84cc16\",\"#f43f5e\",\"#6366f1\"]"
  """
  def json_palette do
    Jason.encode!(@official_palette)
  end

  @doc """
  Returns the primary color (first color in the palette).
  
  ## Examples
  
      iex> TrifleWeb.DesignSystem.ChartColors.primary()
      "#14b8a6"
  """
  def primary, do: hd(@official_palette)
end