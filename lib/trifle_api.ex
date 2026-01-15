defmodule TrifleApi do
  @moduledoc """
  The entrypoint for defining the Trifle API interface.
  This module handles all API functionality under /api/v1 routes.
  """

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:json]

      import Plug.Conn
      import TrifleApi.Gettext

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: TrifleWeb.Endpoint,
        router: TrifleApp.Router,
        statics: []
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
