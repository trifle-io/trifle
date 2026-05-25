defmodule TrifleApp.Layouts do
  use TrifleApp, :html

  embed_templates "layouts/*"

  alias TrifleWeb.SidebarHelpers

  @command_palette_section_order [
    "Actions",
    "Recent",
    "Triggered",
    "Dashboards",
    "Monitors",
    "Databases",
    "Projects"
  ]

  def command_palette_trigger(assigns) do
    ~H"""
    <button
      type="button"
      id="command-palette-trigger"
      data-command-palette-trigger
      class="group relative flex w-full items-center rounded-[1.15rem] border border-slate-200/80 bg-white/90 text-left text-sm font-medium text-slate-500 shadow-[inset_0_1px_0_rgba(255,255,255,0.9),0_16px_28px_-30px_rgba(15,23,42,0.55)] transition duration-200 ease-out hover:border-teal-300/80 hover:bg-white hover:text-slate-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-teal-500/70 dark:border-slate-700/80 dark:bg-slate-900/75 dark:text-slate-300 dark:shadow-none dark:hover:border-teal-400/40 dark:hover:bg-slate-800 dark:hover:text-white"
      data-fast-tooltip
      x-bind:data-tooltip={SidebarHelpers.compact_tooltip_expr("Search and navigate")}
      x-bind:data-tooltip-placement={SidebarHelpers.compact_tooltip_placement_expr()}
      x-bind:class="compact ? 'mx-auto h-11 w-11 justify-center p-0' : 'px-3.5 py-3'"
      x-on:click="openCommandPalette($event.currentTarget)"
      aria-haspopup="dialog"
      x-bind:aria-expanded="commandPaletteOpen.toString()"
    >
      <span
        class="flex shrink-0 items-center justify-center rounded-xl border border-slate-200/70 bg-white/80 text-slate-400 transition group-hover:text-teal-600 dark:border-slate-700/80 dark:bg-slate-900 dark:text-slate-400 dark:group-hover:border-teal-400/40 dark:group-hover:bg-teal-400/10 dark:group-hover:text-teal-200"
        x-bind:class="compact ? 'h-9 w-9' : 'h-8 w-8'"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.7"
          stroke="currentColor"
          class="h-4 w-4"
          aria-hidden="true"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="m21 21-4.35-4.35m1.35-5.4a6.75 6.75 0 1 1-13.5 0 6.75 6.75 0 0 1 13.5 0Z"
          />
        </svg>
      </span>
      <span class="ml-3 min-w-0 flex-1" x-cloak x-show="!compact" x-transition.opacity.duration.150ms>
        <span class="block truncate">Search</span>
      </span>
      <span
        class={shortcut_hint_classes()}
        x-cloak
        x-show="!compact"
        x-transition.opacity.duration.150ms
        x-text="commandShortcutLabel()"
      />
    </button>
    """
  end

  def command_palette_modal(assigns) do
    assigns = assign(assigns, :sections, command_palette_sections(assigns[:items] || []))

    ~H"""
    <div
      id="command-palette-overlay"
      class="fixed inset-0 z-[130] flex items-start justify-center bg-slate-900/40 px-3 py-[10vh] backdrop-blur-sm dark:bg-slate-900/75 sm:px-6"
      role="presentation"
      x-cloak
      x-show="commandPaletteOpen"
      x-transition.opacity.duration.150ms
      x-on:click.self="closeCommandPalette()"
      x-bind:aria-hidden="(!commandPaletteOpen).toString()"
    >
      <div
        id="command-palette-dialog"
        class="flex max-h-[min(42rem,80vh)] w-full max-w-2xl flex-col overflow-hidden rounded-2xl border border-white/80 bg-white shadow-[0_34px_90px_-38px_rgba(15,23,42,0.62)] ring-1 ring-slate-900/5 dark:border-slate-700/80 dark:bg-slate-900 dark:shadow-none dark:ring-white/10 dark:[color-scheme:dark]"
        role="dialog"
        aria-modal="true"
        aria-labelledby="command-palette-title"
        x-on:keydown="handleCommandPalettePanelKeydown($event)"
      >
        <h2 id="command-palette-title" class="sr-only">Search and navigate</h2>
        <div class="flex items-center gap-3 border-b border-slate-200/80 px-4 py-3 dark:border-slate-800">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.7"
            stroke="currentColor"
            class="h-5 w-5 shrink-0 text-slate-400 dark:text-slate-400"
            aria-hidden="true"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="m21 21-4.35-4.35m1.35-5.4a6.75 6.75 0 1 1-13.5 0 6.75 6.75 0 0 1 13.5 0Z"
            />
          </svg>
          <input
            id="command-palette-input"
            type="search"
            autocomplete="off"
            spellcheck="false"
            placeholder="Search dashboards, monitors, databases..."
            name="command_palette_search"
            aria-label="Search workspace resources"
            class="min-w-0 flex-1 border-0 bg-transparent p-0 text-base text-slate-900 placeholder:text-slate-400 focus:ring-0 dark:text-white dark:placeholder:text-slate-500 dark:[color-scheme:dark]"
            x-model="commandPaletteQuery"
            x-on:input="queueCommandPaletteRefresh()"
            x-on:keydown.arrow-down.prevent="moveCommandPaletteActive(1)"
            x-on:keydown.arrow-up.prevent="moveCommandPaletteActive(-1)"
            x-on:keydown.enter.prevent="selectActiveCommandPaletteItem()"
            x-bind:aria-activedescendant="commandPaletteActiveItemId || null"
            role="combobox"
            aria-controls="command-palette-results"
            aria-autocomplete="list"
          />
          <button
            type="button"
            class="inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-xl text-slate-400 transition hover:bg-slate-100 hover:text-slate-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 dark:text-slate-400 dark:hover:bg-slate-800 dark:hover:text-white"
            x-on:click="closeCommandPalette()"
            aria-label="Close search"
          >
            <TrifleApp.SidebarIcons.icon name="hero-x-mark" class="h-4 w-4" />
          </button>
        </div>

        <div
          id="command-palette-results"
          class="min-h-0 flex-1 overflow-y-auto px-2 py-3"
          role="listbox"
        >
          <%= for section <- @sections do %>
            <section
              data-command-palette-section={section.label}
              hidden={section.default_hidden}
              class="pb-2"
            >
              <p class="px-3 pb-1.5 pt-2 text-xs font-semibold tracking-[0.04em] text-slate-500 dark:text-slate-400">
                {section.label}
              </p>
              <div class="space-y-1">
                <%= for item <- section.items do %>
                  <button
                    type="button"
                    id={item["dom_id"]}
                    data-command-palette-item
                    data-command-palette-search-text={item["search_text"]}
                    data-command-palette-searchable={to_string(item["searchable"])}
                    data-command-palette-default-visible={
                      to_string(item["default_section"] == section.label)
                    }
                    data-command-palette-to={item["to"]}
                    data-command-palette-action={item["action"]}
                    hidden={item["default_section"] != section.label}
                    role="option"
                    aria-selected="false"
                    class="group flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left text-sm text-slate-700 transition hover:bg-slate-900/5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500/70 dark:text-slate-200 dark:hover:bg-slate-800/80 dark:hover:text-white"
                    x-bind:class="commandPaletteItemActive($el) ? 'bg-slate-900/5 text-slate-900 dark:bg-slate-800 dark:text-white' : ''"
                    x-on:mousemove="activateCommandPaletteElement($event.currentTarget)"
                    x-on:click="selectCommandPaletteElement($event.currentTarget)"
                  >
                    <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl border border-slate-200/80 bg-slate-50 text-slate-500 transition group-hover:border-teal-200 group-hover:bg-teal-50 group-hover:text-teal-700 dark:border-slate-700/80 dark:bg-slate-800 dark:text-slate-300 dark:group-hover:border-teal-400/40 dark:group-hover:bg-teal-400/10 dark:group-hover:text-teal-200">
                      <TrifleApp.SidebarIcons.icon
                        name={item["icon"] || "hero-arrow-uturn-left"}
                        class={
                          if item["icon"] == "chef-hat-alt-2",
                            do: "h-5 w-5 stroke-[1.35]",
                            else: "h-4 w-4"
                        }
                      />
                    </span>
                    <span class="min-w-0 flex-1">
                      <span class="block truncate font-medium">{item["title"]}</span>
                      <span
                        :if={item["subtitle"]}
                        class="mt-0.5 block truncate text-xs text-slate-500 dark:text-slate-400"
                      >
                        {item["subtitle"]}
                      </span>
                    </span>
                    <span class="text-xs text-slate-300 opacity-0 transition group-hover:opacity-100 dark:text-slate-500">
                      ↵
                    </span>
                  </button>
                <% end %>
              </div>
            </section>
          <% end %>

          <div
            data-command-palette-empty
            hidden
            class="px-4 py-12 text-center text-sm text-slate-500 dark:text-slate-400"
          >
            No matching resources.
          </div>
        </div>

        <div class="flex items-center gap-4 border-t border-slate-200/80 bg-slate-50/80 px-4 py-2.5 text-xs text-slate-500 dark:border-slate-800 dark:bg-slate-800/60 dark:text-slate-400">
          <span class="inline-flex items-center gap-1">
            <kbd class="rounded border border-slate-200 bg-white px-1.5 py-0.5 text-[0.68rem] font-medium text-slate-500 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-300">
              ↑↓
            </kbd>
            to navigate
          </span>
          <span class="inline-flex items-center gap-1">
            <kbd class="rounded border border-slate-200 bg-white px-1.5 py-0.5 text-[0.68rem] font-medium text-slate-500 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-300">
              Enter
            </kbd>
            to open
          </span>
          <span class="ml-auto inline-flex items-center gap-1">
            <kbd class="rounded border border-slate-200 bg-white px-1.5 py-0.5 text-[0.68rem] font-medium text-slate-500 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-300">
              Esc
            </kbd>
            to close
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr :socket, :any, required: true
  attr :item, :map, required: true

  def sidebar_link(assigns) do
    assigns =
      assigns
      |> assign(:active?, active_nav?(assigns.socket, assigns.item.menu))
      |> assign(:chat_toggle?, Map.get(assigns.item, :toggle_chat, false))
      |> assign(:shortcut_hint?, Map.get(assigns.item, :shortcut_hint, false))
      |> assign(:tooltip_expr, sidebar_tooltip_expr(assigns.item))
      |> assign(:icon_size_style, sidebar_icon_size_style(assigns.item))
      |> assign(:icon_bind_attrs, [
        {"x-bind:style",
         "compact ? '#{sidebar_compact_icon_size_style(assigns.item)}' : '#{sidebar_icon_size_style(assigns.item)}'"}
      ])

    link_attrs =
      if assigns.chat_toggle? do
        [
          {"type", "button"},
          {"x-on:click", "toggleChat(); closeMobile()"}
        ]
      else
        if(Map.get(assigns.item, :use_href, false),
          do: [href: assigns.item.to],
          else: [navigate: assigns.item.to]
        )
      end ++
        [
          {"data-fast-tooltip", true},
          {"x-bind:data-tooltip", assigns.tooltip_expr},
          {"x-bind:data-tooltip-placement", SidebarHelpers.compact_tooltip_placement_expr()}
        ]

    assigns = assign(assigns, :link_attrs, link_attrs)

    ~H"""
    <%= if @chat_toggle? do %>
      <button
        {@link_attrs}
        aria-label={@item.label}
        class={[
          "sidebar-nav-link group relative block w-full rounded-[1.15rem] text-sm font-semibold transition duration-200 ease-out focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500/70 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-slate-900",
          SidebarHelpers.sidebar_link_classes(@active?, :teal)
        ]}
      >
        <span
          :if={!@active?}
          class={[
            "pointer-events-none absolute left-0.5 top-1/2 h-7 w-0.5 -translate-y-1/2 rounded-full opacity-0 transition-opacity duration-200 ease-out group-hover:opacity-100",
            SidebarHelpers.sidebar_hover_line_classes(:teal)
          ]}
        />
        <span
          :if={@active?}
          class={[
            "pointer-events-none absolute left-0.5 top-1/2 h-7 w-0.5 -translate-y-1/2 rounded-full",
            SidebarHelpers.sidebar_active_line_classes(:teal)
          ]}
        />
        <span
          class="flex items-center gap-3"
          x-bind:class="compact ? 'mx-auto h-9 w-9 justify-center px-0' : 'min-h-[3.1rem] w-full justify-start px-3.5'"
        >
          <span class={[
            "flex h-9 w-9 shrink-0 items-center justify-center rounded-2xl transition",
            SidebarHelpers.sidebar_icon_shell_classes(@active?, :teal)
          ]}>
            <TrifleApp.SidebarIcons.icon
              name={@item.icon}
              class={[
                "shrink-0 transition",
                SidebarHelpers.sidebar_icon_classes(@active?, :teal)
              ]}
              style={@icon_size_style}
              {@icon_bind_attrs}
            />
          </span>
          <span x-cloak x-show="!compact" x-transition.opacity.duration.150ms class="min-w-0 flex-1">
            <span class="flex items-center justify-between gap-2">
              <span class="min-w-0 truncate">{@item.label}</span>
              <span
                :if={@shortcut_hint?}
                class={shortcut_hint_classes()}
                x-text="chatShortcutLabel()"
              />
            </span>
          </span>
        </span>
      </button>
    <% else %>
      <.link
        {@link_attrs}
        aria-current={if @active?, do: "page"}
        aria-label={@item.label}
        class={[
          "sidebar-nav-link group relative block w-full rounded-[1.15rem] text-sm font-semibold transition duration-200 ease-out focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500/70 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-slate-900",
          SidebarHelpers.sidebar_link_classes(@active?, :teal)
        ]}
      >
        <span
          :if={!@active?}
          class={[
            "pointer-events-none absolute left-0.5 top-1/2 h-7 w-0.5 -translate-y-1/2 rounded-full opacity-0 transition-opacity duration-200 ease-out group-hover:opacity-100",
            SidebarHelpers.sidebar_hover_line_classes(:teal)
          ]}
        />
        <span
          :if={@active?}
          class={[
            "pointer-events-none absolute left-0.5 top-1/2 h-7 w-0.5 -translate-y-1/2 rounded-full",
            SidebarHelpers.sidebar_active_line_classes(:teal)
          ]}
        />
        <span
          class="flex items-center gap-3"
          x-bind:class="compact ? 'mx-auto h-9 w-9 justify-center px-0' : 'min-h-[3.1rem] w-full justify-start px-3.5'"
        >
          <span class={[
            "flex h-9 w-9 shrink-0 items-center justify-center rounded-2xl transition",
            SidebarHelpers.sidebar_icon_shell_classes(@active?, :teal)
          ]}>
            <TrifleApp.SidebarIcons.icon
              name={@item.icon}
              class={[
                "shrink-0 transition",
                SidebarHelpers.sidebar_icon_classes(@active?, :teal)
              ]}
              style={@icon_size_style}
              {@icon_bind_attrs}
            />
          </span>
          <span x-cloak x-show="!compact" x-transition.opacity.duration.150ms class="min-w-0 flex-1">
            <span class="flex items-center justify-between gap-2">
              <span class="min-w-0 truncate">{@item.label}</span>
              <span
                :if={@shortcut_hint?}
                class={shortcut_hint_classes()}
                x-text="chatShortcutLabel()"
              />
            </span>
          </span>
        </span>
      </.link>
    <% end %>
    """
  end

  def nav_items do
    [
      %{menu: :home, label: "Home", to: ~p"/", icon: "sidebar-home"},
      %{
        menu: :chat,
        label: "Mr. Baker",
        icon: "chef-hat-alt-2",
        toggle_chat: true,
        shortcut_hint: true
      },
      %{menu: :dashboards, label: "Dashboards", to: ~p"/dashboards", icon: "sidebar-dashboards"},
      %{menu: :monitors, label: "Monitors", to: ~p"/monitors", icon: "sidebar-monitors"},
      %{menu: :explore, label: "Explore", to: ~p"/explore", icon: "sidebar-explore"},
      Trifle.Config.projects_enabled?() &&
        %{menu: :projects, label: "Projects", to: ~p"/projects", icon: "sidebar-projects"},
      %{menu: :databases, label: "Databases", to: ~p"/dbs", icon: "sidebar-databases"}
    ]
    |> Enum.filter(& &1)
  end

  def secondary_nav_items(current_user, current_membership) do
    [
      current_membership && organization_item(),
      current_user && current_user.is_admin && admin_console_item()
    ]
    |> Enum.filter(& &1)
  end

  def current_nav_label(socket) do
    current_user = Map.get(socket.assigns, :current_user)
    current_membership = Map.get(socket.assigns, :current_membership)

    case Enum.find(
           sidebar_nav_items(current_user, current_membership),
           &active_nav?(socket, &1.menu)
         ) do
      %{label: label} -> label
      _ -> "Workspace"
    end
  end

  defp organization_item do
    %{
      menu: :organization,
      label: "Organization",
      to: ~p"/organization/profile",
      icon: "sidebar-organization"
    }
  end

  defp admin_console_item do
    %{
      menu: :admin_console,
      label: "Admin Console",
      to: "/admin",
      icon: "sidebar-admin",
      use_href: true
    }
  end

  defp sidebar_nav_items(current_user, current_membership) do
    nav_items() ++ secondary_nav_items(current_user, current_membership)
  end

  defp sidebar_tooltip_expr(%{shortcut_hint: true, label: label}) do
    compact_label = Phoenix.json_library().encode!(label)
    "compact ? #{compact_label} + ' • ' + chatShortcutLabel() : null"
  end

  defp sidebar_tooltip_expr(%{label: label}), do: SidebarHelpers.compact_tooltip_expr(label)

  defp shortcut_hint_classes do
    "inline-flex h-7 shrink-0 items-center justify-center rounded-xl border border-slate-200/70 bg-white/90 px-2.5 text-[0.68rem] font-medium leading-none text-slate-500 shadow-[inset_0_1px_0_rgba(255,255,255,0.9)] dark:border-slate-700/80 dark:bg-slate-900/75 dark:text-slate-300 dark:shadow-none"
  end

  defp command_palette_sections(items) do
    items = List.wrap(items)

    @command_palette_section_order
    |> Enum.map(fn label ->
      section_items =
        Enum.filter(items, fn item ->
          item["default_section"] == label || item["search_section"] == label
        end)

      %{
        label: label,
        items: section_items,
        default_hidden: not Enum.any?(section_items, &(Map.get(&1, "default_section") == label))
      }
    end)
    |> Enum.reject(&Enum.empty?(&1.items))
  end

  defp sidebar_icon_size_style(%{icon: "chef-hat-alt-2"}),
    do: "height: 1.38rem; width: 1.38rem; stroke-width: 1.35;"

  defp sidebar_icon_size_style(_item), do: "height: 1.05rem; width: 1.05rem;"

  defp sidebar_compact_icon_size_style(%{icon: "chef-hat-alt-2"}),
    do: "height: 1.5rem; width: 1.5rem; stroke-width: 1.35;"

  defp sidebar_compact_icon_size_style(_item), do: "height: 1.2rem; width: 1.2rem;"

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

      {:projects, TrifleApp.ProjectTranspondersLive} ->
        true

      {:projects, TrifleApp.ProjectBillingLive} ->
        true

      {:databases, TrifleApp.DatabasesLive} ->
        true

      {:databases, TrifleApp.DatabaseTranspondersLive} ->
        true

      {:databases, TrifleApp.DatabaseSettingsLive} ->
        true

      {:databases, TrifleApp.DatabaseRedirectLive} ->
        true

      {:organization, TrifleApp.OrganizationRedirectLive} ->
        true

      {:organization, TrifleApp.OrganizationProfileLive} ->
        true

      {:organization, TrifleApp.OrganizationUsersLive} ->
        true

      {:organization, TrifleApp.OrganizationSSOLive} ->
        true

      {:organization, TrifleApp.OrganizationDeliveryLive} ->
        true

      {:organization, TrifleApp.OrganizationTokensLive} ->
        true

      {:organization, TrifleApp.OrganizationConnectorsLive} ->
        true

      {:organization, TrifleApp.OrganizationBillingLive} ->
        true

      {:dashboards, _} ->
        Map.get(socket.assigns, :nav_section) == :dashboards

      {:monitors, _} ->
        Map.get(socket.assigns, :nav_section) == :monitors

      {:home, _} ->
        Map.get(socket.assigns, :nav_section) == :home

      {:projects, _} ->
        Map.get(socket.assigns, :nav_section) == :projects

      {:databases, _} ->
        Map.get(socket.assigns, :nav_section) == :databases

      {:explore, _} ->
        Map.get(socket.assigns, :nav_section) == :explore

      {:chat, _} ->
        Map.get(socket.assigns, :nav_section) == :chat

      {:organization, _} ->
        Map.get(socket.assigns, :nav_section) == :organization

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

    attrs =
      Phoenix.HTML.attributes_escape(
        src: "https://www.gravatar.com/avatar/#{hash}?s=150&d=identicon",
        class: "h-8 w-8 rounded-full",
        alt: ""
      )
      |> Phoenix.HTML.safe_to_string()

    Phoenix.HTML.raw("<img#{attrs} />")
  end
end
