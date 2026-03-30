defmodule TrifleWeb.SidebarHelpers do
  @moduledoc """
  Shared style and tooltip helpers for the client and admin sidebars.
  """

  def compact_tooltip_expr(text) when is_binary(text) do
    "compact ? #{Phoenix.json_library().encode!(text)} : null"
  end

  def compact_tooltip_placement_expr do
    "compact ? 'right' : null"
  end

  def sidebar_link_classes(false, _accent) do
    "text-slate-600 hover:text-slate-950 dark:text-slate-300 dark:hover:text-white"
  end

  def sidebar_link_classes(true, :teal) do
    "text-slate-950 dark:text-white"
  end

  def sidebar_link_classes(true, :orange) do
    "text-slate-950 dark:text-white"
  end

  def sidebar_active_line_classes(:teal) do
    "bg-teal-500 shadow-[0_0_0_1px_rgba(20,184,166,0.16),0_0_18px_rgba(20,184,166,0.26)] dark:bg-teal-300 dark:shadow-[0_0_0_1px_rgba(94,234,212,0.12),0_0_18px_rgba(94,234,212,0.2)]"
  end

  def sidebar_active_line_classes(:orange) do
    "bg-orange-500 shadow-[0_0_0_1px_rgba(249,115,22,0.14),0_0_18px_rgba(249,115,22,0.24)] dark:bg-orange-300 dark:shadow-[0_0_0_1px_rgba(253,186,116,0.12),0_0_18px_rgba(253,186,116,0.2)]"
  end

  def sidebar_hover_line_classes(:teal) do
    "bg-teal-400/50 dark:bg-teal-200/40"
  end

  def sidebar_hover_line_classes(:orange) do
    "bg-orange-400/50 dark:bg-orange-200/40"
  end

  def sidebar_icon_shell_classes(false, _accent) do
    "text-slate-500 group-hover:text-slate-800 dark:text-slate-400 dark:group-hover:text-slate-100"
  end

  def sidebar_icon_shell_classes(true, :teal) do
    "text-teal-700 dark:text-teal-200"
  end

  def sidebar_icon_shell_classes(true, :orange) do
    "text-orange-700 dark:text-orange-200"
  end

  def sidebar_icon_classes(false, _accent), do: "text-inherit"
  def sidebar_icon_classes(true, _accent), do: "text-inherit"
end
