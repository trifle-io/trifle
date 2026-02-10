defmodule TrifleAdmin do
  @moduledoc """
  The entrypoint for defining the Trifle admin interface.
  This module handles all admin functionality under /admin routes.
  """

  def static_paths, do: ~w(assets fonts images favicon.ico favicon_dark favicon_light robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: TrifleAdmin.Layouts]

      import Plug.Conn
      import TrifleAdmin.Gettext

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {TrifleAdmin.Layouts, :app}

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML
      import TrifleApp.CoreComponents
      import TrifleAdmin.Gettext

      # Design System Components
      import TrifleApp.DesignSystem.AdminTable
      import TrifleApp.DesignSystem.Modal
      import TrifleApp.DesignSystem.FormField
      import TrifleApp.DesignSystem.FormButtons
      import TrifleApp.DesignSystem.FormContainer
      import TrifleApp.DesignSystem.DatabaseLabel

      alias Phoenix.LiveView.JS

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: TrifleWeb.Endpoint,
        router: TrifleWeb.Router,
        statics: TrifleAdmin.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
