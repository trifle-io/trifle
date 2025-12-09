defmodule TrifleApp.Layouts do
  use TrifleApp, :html

  embed_templates "layouts/*"

  def nav_class(socket, menu, variant \\ :desktop) do
    base_active =
      case variant do
        :mobile ->
          "block px-3 py-2 text-base font-medium text-white border-b-2 border-teal-400"

        _ ->
          "text-white px-3 py-2 text-sm font-medium border-b-2 border-teal-400 shadow-[0_10px_18px_-12px_rgba(13,148,136,0.9)]"
      end

    base_inactive =
      case variant do
        :mobile ->
          "text-gray-300 hover:text-white block px-3 py-2 text-base font-medium border-b-2 border-transparent hover:border-teal-400 hover:bg-gray-800/60"

        _ ->
          "text-gray-300 hover:text-white px-3 py-2 text-sm font-medium border-b-2 border-transparent hover:border-teal-400 hover:bg-gray-800/60"
      end

    if active_nav?(socket, menu) do
      base_active
    else
      base_inactive
    end
  end

  def live_active_link(socket, menu, label, opts) do
    to = Keyword.fetch!(opts, :to)
    variant = Keyword.get(opts, :variant, :desktop)
    assigns = %{socket: socket, menu: menu, label: label, to: to, variant: variant}

    ~H"""
    <.link navigate={@to} class={TrifleApp.Layouts.nav_class(@socket, @menu, @variant)}>
      {@label}
    </.link>
    """
  end

  defp active_nav?(%Phoenix.LiveView.Socket{} = socket, menu) do
    view = socket.view

    case {menu, view} do
      {:home, TrifleApp.HomeLive} ->
        true

      {:dashboards, TrifleApp.AppLive} ->
        true

      {:dashboards, TrifleApp.DashboardsLive} ->
        true

      {:dashboards, TrifleApp.DashboardLive} ->
        true

      {:monitors, TrifleApp.MonitorsLive} ->
        true

      {:monitors, TrifleApp.MonitorLive} ->
        true

      {:explore, TrifleApp.ExploreLive} ->
        true

      {:projects, TrifleApp.ProjectsLive} ->
        true

      {:projects, TrifleApp.ProjectSettingsLive} ->
        true

      {:projects, TrifleApp.ProjectTokensLive} ->
        true

      {:projects, TrifleApp.ProjectTranspondersLive} ->
        true

      {:databases, TrifleApp.DatabasesLive} ->
        true

      {:databases, TrifleApp.DatabaseTranspondersLive} ->
        true

      {:databases, TrifleApp.DatabaseSettingsLive} ->
        true

      {:databases, TrifleApp.DatabaseRedirectLive} ->
        true

      {:chat, TrifleApp.ChatLive} ->
        true

      {:monitors, _} ->
        Map.get(socket.assigns, :nav_section) == :monitors

      {:home, _} ->
        Map.get(socket.assigns, :nav_section) == :home

      {:projects, _} ->
        Map.get(socket.assigns, :nav_section) == :projects

      {:databases, _} ->
        Map.get(socket.assigns, :nav_section) == :databases

      _ ->
        false
    end
  end

  defp active_nav?(_, _), do: false

  def gravatar(email) do
    hash =
      email
      |> String.trim()
      |> String.downcase()
      |> :erlang.md5()
      |> Base.encode16(case: :lower)

    img = "https://www.gravatar.com/avatar/#{hash}?s=150&d=identicon"
    # img_tag(img, class: "h-8 w-8 rounded-full")
    Phoenix.HTML.raw("<img src=#{img} class='h-8 w-8 rounded-full'></img>")
  end
end
