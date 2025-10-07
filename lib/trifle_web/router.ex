defmodule TrifleWeb.Router do
  use Phoenix.Router, helpers: false

  import Phoenix.LiveView.Router
  import TrifleApp.UserAuth

  pipeline :admin_browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {TrifleAdmin.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  scope "/admin", TrifleAdmin, as: :admin do
    pipe_through [:admin_browser, :require_authenticated_user]

    live_session :admin_authenticated,
      on_mount: [{TrifleApp.UserAuth, :ensure_authenticated}] do
      live "/", AdminLive, :index
      live "/users", UsersLive, :index
      live "/databases", DatabasesLive, :index
      live "/databases/new", DatabasesLive, :new
      live "/databases/:id/edit", DatabasesLive, :edit
      live "/databases/:id/show", DatabasesLive, :show
    end
  end

  forward "/", TrifleApp.Router
end
