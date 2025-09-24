defmodule TrifleApp.OrganizationLive.Navigation do
  use TrifleApp, :html

  attr :active_tab, :atom

  def nav(assigns) do
    ~H"""
    <div class="mb-6 border-b border-gray-200 dark:border-slate-700">
      <nav class="-mb-px flex flex-wrap gap-4" aria-label="Organization tabs">
        <.link navigate={~p"/organization"} class={tab_link_classes(@active_tab == :profile)}>
          <svg
            class={tab_icon_classes(@active_tab == :profile)}
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M20.25 14.15v4.25c0 1.094-.787 2.036-1.872 2.18-2.087.277-4.216.42-6.378.42s-4.291-.143-6.378-.42c-1.085-.144-1.872-1.086-1.872-2.18v-4.25m16.5 0a2.18 2.18 0 0 0 .75-1.661V8.706c0-1.081-.768-2.015-1.837-2.175a48.114 48.114 0 0 0-3.413-.387m4.5 8.006c-.194.165-.42.295-.673.38A23.978 23.978 0 0 1 12 15.75c-2.648 0-5.195-.429-7.577-1.22a2.016 2.016 0 0 1-.673-.38m0 0A2.18 2.18 0 0 1 3 12.489V8.706c0-1.081.768-2.015 1.837-2.175a48.111 48.111 0 0 1 3.413-.387m7.5 0V5.25A2.25 2.25 0 0 0 13.5 3h-3a2.25 2.25 0 0 0-2.25 2.25v.894m7.5 0a48.667 48.667 0 0 0-7.5 0M12 12.75h.008v.008H12v-.008Z"
            />
          </svg>
          <span class="hidden sm:block">Profile</span>
        </.link>

        <.link navigate={~p"/organization/users"} class={tab_link_classes(@active_tab == :users)}>
          <svg
            class={tab_icon_classes(@active_tab == :users)}
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z"
            />
          </svg>
          <span class="hidden sm:block">Users</span>
        </.link>

        <.link
          navigate={~p"/organization/billing"}
          class={tab_link_classes(@active_tab == :billing, :right)}
        >
          <svg
            class={tab_icon_classes(@active_tab == :billing)}
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M2.25 18.75a60.07 60.07 0 0 1 15.797 2.101c.727.198 1.453-.342 1.453-1.096V18.75M3.75 4.5v.75A.75.75 0 0 1 3 6h-.75m0 0v-.375c0-.621.504-1.125 1.125-1.125H20.25M2.25 6v9m18-10.5v.75c0 .414.336.75.75.75h.75m-1.5-1.5h.375c.621 0 1.125.504 1.125 1.125v9.75c0 .621-.504 1.125-1.125 1.125h-.375m1.5-1.5H21a.75.75 0 0 0-.75.75v.75m0 0H3.75m0 0h-.375a1.125 1.125 0 0 1-1.125-1.125V15m1.5 1.5v-.75A.75.75 0 0 0 3 15h-.75M15 10.5a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm3 0h.008v.008H18V10.5Zm-12 0h.008v.008H6V10.5Z"
            />
          </svg>
          <span class="hidden sm:block">Billing</span>
        </.link>
      </nav>
    </div>
    """
  end

  defp tab_link_classes(active, align \\ :left)

  defp tab_link_classes(true, align) do
    align_class = if align == :right, do: "float-right", else: ""

    "group inline-flex items-center border-b-2 border-teal-500 text-teal-600 dark:text-teal-400 py-4 px-1 text-sm font-medium " <>
      align_class
  end

  defp tab_link_classes(false, align) do
    align_class = if align == :right, do: "float-right", else: ""
    base = "group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium"

    base <>
      " border-transparent text-gray-500 dark:text-slate-400 hover:border-gray-300 dark:hover:border-slate-500 hover:text-gray-700 dark:hover:text-slate-300 " <>
      align_class
  end

  defp tab_icon_classes(true) do
    "-ml-0.5 mr-2 h-5 w-5 text-teal-400 group-hover:text-teal-500"
  end

  defp tab_icon_classes(false) do
    "-ml-0.5 mr-2 h-5 w-5 text-gray-400 dark:text-slate-400 group-hover:text-gray-500 dark:group-hover:text-slate-300"
  end
end
