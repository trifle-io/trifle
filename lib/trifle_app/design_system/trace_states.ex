defmodule TrifleApp.DesignSystem.TraceStates do
  @moduledoc "Consistent semantic colors for trace states, independent of path and filtering."
  alias TrifleApp.DesignSystem.ChartColors

  def color("success"), do: ChartColors.color_for(0)
  def color("warning"), do: ChartColors.color_for(6)
  def color("error"), do: ChartColors.color_for(2)
  def color("running"), do: ChartColors.color_for(8)
  def color(_), do: "#94a3b8"
end
