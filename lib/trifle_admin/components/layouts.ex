defmodule TrifleAdmin.Layouts do
  use TrifleAdmin, :html

  embed_templates "layouts/*"

  def nav_class(socket, menu, variant \\ :desktop) do
    base_active =
      case variant do
        :mobile ->
          "block px-3 py-2 text-base font-medium text-orange-700 dark:text-orange-300 border-b-2 border-orange-400"

        _ ->
          "text-orange-700 dark:text-orange-300 px-3 py-2 text-sm font-medium border-b-2 border-orange-400 shadow-[0_10px_18px_-12px_rgba(249,115,22,0.7)]"
      end

    base_inactive =
      case variant do
        :mobile ->
          "text-slate-600 dark:text-slate-300 hover:text-orange-700 dark:hover:text-orange-300 block px-3 py-2 text-base font-medium border-b-2 border-transparent hover:border-orange-400"

        _ ->
          "text-slate-600 dark:text-slate-300 hover:text-orange-700 dark:hover:text-orange-300 px-3 py-2 text-sm font-medium border-b-2 border-transparent hover:border-orange-400"
      end

    if active_nav?(socket, menu), do: base_active, else: base_inactive
  end

  def live_active_link(socket, menu, label, opts) do
    to = Keyword.fetch!(opts, :to)
    variant = Keyword.get(opts, :variant, :desktop)
    assigns = %{socket: socket, menu: menu, label: label, to: to, variant: variant}

    ~H"""
    <.link navigate={@to} class={TrifleAdmin.Layouts.nav_class(@socket, @menu, @variant)}>
      {@label}
    </.link>
    """
  end

  defp active_nav?(%Phoenix.LiveView.Socket{} = socket, menu) do
    view = socket.view

    case {menu, view} do
      {:dashboard, TrifleAdmin.AdminLive} -> true
      {:organizations, TrifleAdmin.OrganizationsLive} -> true
      {:users, TrifleAdmin.UsersLive} -> true
      {:projects, TrifleAdmin.ProjectsLive} -> true
      {:project_clusters, TrifleAdmin.ProjectClustersLive} -> true
      {:databases, TrifleAdmin.DatabasesLive} -> true
      {:dashboards, TrifleAdmin.DashboardsLive} -> true
      {:monitors, TrifleAdmin.MonitorsLive} -> true
      _ -> false
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
