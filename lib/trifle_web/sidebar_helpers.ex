defmodule TrifleWeb.SidebarHelpers do
  @moduledoc """
  Shared style and tooltip helpers for the client and admin sidebars.
  """

  def compact_tooltip_expr(text) when is_binary(text) do
    "compact ? #{Phoenix.json_library().encode!(text)} : null"
  end

  def sidebar_link_classes(false, _accent) do
    "text-slate-600 hover:bg-white/95 hover:text-slate-950 dark:text-slate-300 dark:hover:bg-white/[0.06] dark:hover:text-white"
  end

  def sidebar_link_classes(true, :teal) do
    "bg-teal-50/90 text-slate-950 ring-1 ring-inset ring-teal-200/90 shadow-[0_14px_28px_-24px_rgba(13,148,136,0.42)] dark:bg-teal-400/[0.08] dark:text-white dark:ring-teal-400/18 dark:shadow-[0_18px_30px_-28px_rgba(20,184,166,0.4)]"
  end

  def sidebar_link_classes(true, :orange) do
    "bg-orange-50/92 text-slate-950 ring-1 ring-inset ring-orange-200/90 shadow-[0_14px_28px_-24px_rgba(249,115,22,0.4)] dark:bg-orange-400/[0.08] dark:text-white dark:ring-orange-400/18 dark:shadow-[0_18px_30px_-28px_rgba(251,146,60,0.38)]"
  end

  def sidebar_icon_shell_classes(false, _accent) do
    "bg-white/90 text-slate-500 ring-slate-200/80 group-hover:bg-white group-hover:text-slate-800 dark:bg-slate-900/80 dark:text-slate-400 dark:ring-white/10 dark:group-hover:bg-slate-800 dark:group-hover:text-slate-100"
  end

  def sidebar_icon_shell_classes(true, :teal) do
    "bg-teal-500/12 text-teal-700 ring-teal-300/70 shadow-inner shadow-white/70 dark:bg-teal-400/12 dark:text-teal-200 dark:ring-teal-400/30 dark:shadow-transparent"
  end

  def sidebar_icon_shell_classes(true, :orange) do
    "bg-orange-500/12 text-orange-700 ring-orange-300/70 shadow-inner shadow-white/70 dark:bg-orange-400/12 dark:text-orange-200 dark:ring-orange-400/30 dark:shadow-transparent"
  end

  def sidebar_icon_classes(false, _accent), do: "text-inherit"
  def sidebar_icon_classes(true, :teal), do: "text-teal-700 dark:text-teal-200"
  def sidebar_icon_classes(true, :orange), do: "text-orange-700 dark:text-orange-200"
end
