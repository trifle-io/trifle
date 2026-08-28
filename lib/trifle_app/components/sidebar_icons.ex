defmodule TrifleApp.SidebarIcons do
  use Phoenix.Component

  attr :name, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global

  def icon(assigns) do
    ~H"""
    <%= case @name do %>
      <% "sidebar-overview" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M2.25 7.125C2.25 6.504 2.754 6 3.375 6h6c.621 0 1.125.504 1.125 1.125v3.75c0 .621-.504 1.125-1.125 1.125h-6a1.125 1.125 0 0 1-1.125-1.125v-3.75ZM14.25 8.625c0-.621.504-1.125 1.125-1.125h5.25c.621 0 1.125.504 1.125 1.125v8.25c0 .621-.504 1.125-1.125 1.125h-5.25a1.125 1.125 0 0 1-1.125-1.125v-8.25ZM3.75 16.125c0-.621.504-1.125 1.125-1.125h5.25c.621 0 1.125.504 1.125 1.125v2.25c0 .621-.504 1.125-1.125 1.125h-5.25a1.125 1.125 0 0 1-1.125-1.125v-2.25Z"
          />
        </svg>
      <% "sidebar-organization" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M3.75 21h16.5M4.5 3h15M5.25 3v18m13.5-18v18M9 6.75h1.5m-1.5 3h1.5m-1.5 3h1.5m3-6H15m-1.5 3H15m-1.5 3H15M9 21v-3.375c0-.621.504-1.125 1.125-1.125h3.75c.621 0 1.125.504 1.125 1.125V21"
          />
        </svg>
      <% "sidebar-users" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z"
          />
        </svg>
      <% "sidebar-projects" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M2.25 12.75V12A2.25 2.25 0 0 1 4.5 9.75h15A2.25 2.25 0 0 1 21.75 12v.75m-8.69-6.44-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44Z"
          />
        </svg>
      <% "sidebar-project-clusters" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M5.25 14.25h13.5m-13.5 0a3 3 0 0 1-3-3m3 3a3 3 0 1 0 0 6h13.5a3 3 0 1 0 0-6m-16.5-3a3 3 0 0 1 3-3h13.5a3 3 0 0 1 3 3m-19.5 0a4.5 4.5 0 0 1 .9-2.7L5.737 5.1a3.375 3.375 0 0 1 2.7-1.35h7.126c1.062 0 2.062.5 2.7 1.35l2.587 3.45a4.5 4.5 0 0 1 .9 2.7m0 0a3 3 0 0 1-3 3m0 3h.008v.008h-.008v-.008Zm0-6h.008v.008h-.008v-.008Zm-3 6h.008v.008h-.008v-.008Zm0-6h.008v.008h-.008v-.008Z"
          />
        </svg>
      <% "sidebar-databases" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125"
          />
        </svg>
      <% "sidebar-dashboards" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M3.75 3v11.25A2.25 2.25 0 0 0 6 16.5h2.25M3.75 3h-1.5m1.5 0h16.5m0 0h1.5m-1.5 0v11.25A2.25 2.25 0 0 1 18 16.5h-2.25m-7.5 0h7.5m-7.5 0-1 3m8.5-3 1 3m0 0 .5 1.5m-.5-1.5h-9.5m0 0-.5 1.5M9 11.25v1.5M12 9v3.75m3-6v6"
          />
        </svg>
      <% "sidebar-monitors" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25M9 16.5v.75m3-3v3M15 12v5.25m-4.5-15H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z"
          />
        </svg>
      <% "sidebar-billing" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M2.25 8.25h19.5M2.25 9h19.5m-16.5 5.25h6m-6 2.25h3m-3.75 3h15a2.25 2.25 0 0 0 2.25-2.25V6.75A2.25 2.25 0 0 0 19.5 4.5h-15a2.25 2.25 0 0 0-2.25 2.25v10.5A2.25 2.25 0 0 0 4.5 19.5Z"
          />
        </svg>
      <% "sidebar-home" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="m2.25 12 8.954-8.955c.44-.439 1.152-.439 1.591 0L21.75 12M4.5 9.75v10.125c0 .621.504 1.125 1.125 1.125H9.75v-4.875c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21h4.125c.621 0 1.125-.504 1.125-1.125V9.75M8.25 21h8.25"
          />
        </svg>
      <% "sidebar-explore" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M3.375 19.5h17.25m-17.25 0a1.125 1.125 0 0 1-1.125-1.125M3.375 19.5h7.5c.621 0 1.125-.504 1.125-1.125m-9.75 0V5.625m0 12.75v-1.5c0-.621.504-1.125 1.125-1.125m18.375 2.625V5.625m0 12.75c0 .621-.504 1.125-1.125 1.125m1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125m0 3.75h-7.5A1.125 1.125 0 0 1 12 18.375m9.75-12.75c0-.621-.504-1.125-1.125-1.125H3.375c-.621 0-1.125.504-1.125 1.125m19.5 0v1.5c0 .621-.504 1.125-1.125 1.125M2.25 5.625v1.5c0 .621.504 1.125 1.125 1.125m0 0h17.25m-17.25 0h7.5c.621 0 1.125.504 1.125 1.125M3.375 8.25c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125m17.25-3.75h-7.5c-.621 0-1.125.504-1.125 1.125m8.625-1.125c.621 0 1.125.504 1.125 1.125v1.5c0 .621-.504 1.125-1.125 1.125m-17.25 0h7.5m-7.5 0c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125M12 10.875v-1.5m0 1.5c0 .621-.504 1.125-1.125 1.125M12 10.875c0 .621.504 1.125 1.125 1.125m-2.25 0c.621 0 1.125.504 1.125 1.125M13.125 12h7.5m-7.5 0c-.621 0-1.125.504-1.125 1.125M20.625 12c.621 0 1.125.504 1.125 1.125v1.5c0 .621-.504 1.125-1.125 1.125m-17.25 0h7.5M12 14.625v-1.5m0 1.5c0 .621-.504 1.125-1.125 1.125M12 14.625c0 .621.504 1.125 1.125 1.125m-2.25 0c.621 0 1.125.504 1.125 1.125m0 1.5v-1.5m0 0c0-.621.504-1.125 1.125-1.125m0 0h7.5"
          />
        </svg>
      <% "chat-mode-pinned" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <rect x="3.75" y="5.25" width="16.5" height="13.5" rx="2.25" />
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M14.25 5.75v12.5M7.5 9.25h3.5M7.5 12h3.5M7.5 14.75h2.25"
          />
        </svg>
      <% "chat-mode-panel" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <rect x="3.75" y="5.25" width="16.5" height="13.5" rx="2.25" />
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M7.5 9.25h4.25M7.5 12h3.25M14.5 7.75h3.25c.552 0 1 .448 1 1v6.5c0 .552-.448 1-1 1H14.5c-.552 0-1-.448-1-1v-6.5c0-.552.448-1 1-1Z"
          />
        </svg>
      <% "chat-mode-fullscreen" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <rect x="3.75" y="5.25" width="16.5" height="13.5" rx="2.25" />
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M8.25 10.5V8.25h2.25M15.75 10.5V8.25H13.5M8.25 13.5v2.25h2.25M15.75 13.5v2.25H13.5"
          />
        </svg>
      <% "chef-hat" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M7.25 12.25c-1.52 0-2.75-1.23-2.75-2.75s1.23-2.75 2.75-2.75c.38 0 .74.08 1.07.22A4.2 4.2 0 0 1 12 4.75c1.65 0 3.1.95 3.8 2.33.31-.09.64-.13.97-.13 1.52 0 2.75 1.23 2.75 2.75s-1.23 2.75-2.75 2.75H7.25Z"
          />
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M8.25 12.25h7.5c.97 0 1.75.78 1.75 1.75v1.25c0 .97-.78 1.75-1.75 1.75h-7.5A1.75 1.75 0 0 1 6.5 15.25V14c0-.97.78-1.75 1.75-1.75Z"
          />
          <path stroke-linecap="round" stroke-linejoin="round" d="M9.5 14.75h5" />
        </svg>
      <% "chef-hat-alt-1" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path stroke-linecap="round" stroke-linejoin="round" d="M5.25 12.5a2.75 2.75 0 0 1 5.5 0" />
          <path stroke-linecap="round" stroke-linejoin="round" d="M8 10.75a4 4 0 0 1 8 0" />
          <path stroke-linecap="round" stroke-linejoin="round" d="M13.25 12.5a2.75 2.75 0 0 1 5.5 0" />
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M7.25 12.5h9.5c.97 0 1.75.78 1.75 1.75v1c0 .97-.78 1.75-1.75 1.75h-9.5A1.75 1.75 0 0 1 5.5 15.25v-1c0-.97.78-1.75 1.75-1.75Z"
          />
          <path stroke-linecap="round" stroke-linejoin="round" d="M9.25 14.75h5.5" />
        </svg>
      <% "chef-hat-tall" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M7.25 13c-1.52 0-2.75-1.23-2.75-2.75S5.73 7.5 7.25 7.5c.25 0 .5.03.73.1A4.55 4.55 0 0 1 12 4.75c1.7 0 3.23.93 4.02 2.38.27-.08.56-.13.86-.13 1.45 0 2.62 1.17 2.62 2.62 0 1.57-1.28 2.83-2.84 2.83H7.25Z"
          />
          <path stroke-linecap="round" stroke-linejoin="round" d="M8 13V11.75m4-5.5V13m4-4.75V13" />
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M7.5 13h9c.97 0 1.75.78 1.75 1.75v1c0 .97-.78 1.75-1.75 1.75h-9a1.75 1.75 0 0 1-1.75-1.75v-1c0-.97.78-1.75 1.75-1.75Z"
          />
          <path stroke-linecap="round" stroke-linejoin="round" d="M9.25 15.25h5.5" />
        </svg>
      <% "chef-hat-alt-2" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M6.75 12.75c-1.52 0-2.75-1.23-2.75-2.75S5.23 7.25 6.75 7.25c.28 0 .55.04.8.12A4.05 4.05 0 0 1 11.5 5c1.55 0 2.93.87 3.63 2.18.3-.09.62-.13.95-.13 1.6 0 2.92 1.3 2.92 2.92 0 1.54-1.19 2.78-2.7 2.86"
          />
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M7.5 12.75h8.25c1.24 0 2.25 1 2.25 2.25v.25c0 1.24-1 2.25-2.25 2.25H7.5a2.25 2.25 0 0 1-2.25-2.25V15c0-1.24 1-2.25 2.25-2.25Z"
          />
          <path stroke-linecap="round" stroke-linejoin="round" d="M9.5 12.75v-2.5" />
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 12.75V9.25" />
          <path stroke-linecap="round" stroke-linejoin="round" d="M14.5 12.75v-2.25" />
        </svg>
      <% "sidebar-ai" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M7.5 8.25h9m-9 3H12m-9.75 1.51c0 1.6 1.123 2.994 2.707 3.227 1.129.166 2.27.293 3.423.379.35.026.67.21.865.501L12 21l2.755-4.133a1.14 1.14 0 0 1 .865-.501 48.172 48.172 0 0 0 3.423-.379c1.584-.233 2.707-1.626 2.707-3.228V6.741c0-1.602-1.123-2.995-2.707-3.228A48.394 48.394 0 0 0 12 3c-2.392 0-4.744.175-7.043.513C3.373 3.746 2.25 5.14 2.25 6.741v6.018Z"
          />
        </svg>
      <% "sidebar-admin" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M9 12.75 11.25 15 15 9.75m-3-7.036A11.959 11.959 0 0 1 3.598 6 11.99 11.99 0 0 0 3 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285Z"
          />
        </svg>
      <% "hero-home" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="m2.25 12 8.954-8.955a1.125 1.125 0 0 1 1.592 0L21.75 12M4.5 9.75V19.5A2.25 2.25 0 0 0 6.75 21.75h10.5a2.25 2.25 0 0 0 2.25-2.25V9.75M9 21.75v-6.375A1.125 1.125 0 0 1 10.125 14.25h3.75A1.125 1.125 0 0 1 15 15.375v6.375"
          />
        </svg>
      <% "hero-users" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M18 18.72a9.094 9.094 0 0 0 3.742-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031A8.966 8.966 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.97 5.97 0 0 0-.94-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0A5.971 5.971 0 0 0 6 18.719m0 0a3 3 0 0 0-4.681 2.72A9.094 9.094 0 0 0 6 18.72m9-11.97a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z"
          />
        </svg>
      <% "hero-squares-2x2" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M3.75 3.75h6.75v6.75H3.75V3.75Zm9.75 0h6.75v6.75H13.5V3.75Zm-9.75 9.75h6.75v6.75H3.75V13.5Zm9.75 0h6.75v6.75H13.5V13.5Z"
          />
        </svg>
      <% "hero-presentation-chart-bar" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M3.75 3.75h16.5v9H3.75v-9Zm3.75 14.25h9m-7.5 0v2.25m6-2.25v2.25M8.25 8.25v1.5m3-3v4.5m3-2.25v2.25"
          />
        </svg>
      <% "hero-credit-card" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M2.25 8.25h19.5M3.75 6h16.5A1.5 1.5 0 0 1 21.75 7.5v9A1.5 1.5 0 0 1 20.25 18H3.75a1.5 1.5 0 0 1-1.5-1.5v-9A1.5 1.5 0 0 1 3.75 6Zm12.75 7.5h2.25"
          />
        </svg>
      <% "hero-arrow-uturn-left" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M9 14.25 4.5 9.75 9 5.25m-4.5 4.5H16.5A3.75 3.75 0 0 1 20.25 13.5v5.25"
          />
        </svg>
      <% "hero-x-mark" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
        </svg>
      <% "hero-ellipsis-horizontal" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M6.75 12a.75.75 0 1 0 0 .001V12Zm5.25 0a.75.75 0 1 0 0 .001V12Zm5.25 0a.75.75 0 1 0 0 .001V12Z"
          />
        </svg>
      <% "hero-circle-stack" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125"
          />
        </svg>
      <% "hero-arrow-path" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M16.023 9.348h4.992V4.356m-1.636 14.288A9 9 0 0 1 5.106 5.106m13.273 13.538 1.636-1.636m0 0H15.02m4.995 0v4.995"
          />
        </svg>
      <% "hero-chevron-double-left" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="m11.25 19.5-7.5-7.5 7.5-7.5m9 15-7.5-7.5 7.5-7.5"
          />
        </svg>
      <% "hero-chevron-double-right" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="m12.75 4.5 7.5 7.5-7.5 7.5m-9-15 7.5 7.5-7.5 7.5"
          />
        </svg>
      <% "hero-bars-3" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5"
          />
        </svg>
      <% "hero-cog-6-tooth" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M10.5 6h3m-7.19 1.31 2.121 2.121m9.758 0 2.121-2.121M6 10.5v3m12-3v3m-9.879 4.379-2.121 2.121m11.758-2.121 2.121 2.121M10.5 18h3M12 15.75A3.75 3.75 0 1 0 12 8.25a3.75 3.75 0 0 0 0 7.5Z"
          />
        </svg>
      <% "hero-arrow-right-on-rectangle" -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M15.75 9V5.25A2.25 2.25 0 0 0 13.5 3h-6A2.25 2.25 0 0 0 5.25 5.25v13.5A2.25 2.25 0 0 0 7.5 21h6a2.25 2.25 0 0 0 2.25-2.25V15m-3-3h8.25m0 0-3-3m3 3-3 3"
          />
        </svg>
      <% _ -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
          aria-hidden="true"
          {@rest}
        >
          <circle cx="12" cy="12" r="9" />
        </svg>
    <% end %>
    """
  end
end
