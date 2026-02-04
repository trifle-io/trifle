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
      live "/organizations", OrganizationsLive, :index
      live "/organizations/:id/show", OrganizationsLive, :show
      live "/users", UsersLive, :index
      live "/users/:id/show", UsersLive, :show
      live "/projects", ProjectsLive, :index
      live "/projects/:id/show", ProjectsLive, :show
      live "/project-clusters", ProjectClustersLive, :index
      live "/project-clusters/new", ProjectClustersLive, :new
      live "/project-clusters/:id/show", ProjectClustersLive, :show
      live "/project-clusters/:id/edit", ProjectClustersLive, :edit
      live "/databases", DatabasesLive, :index
      live "/databases/:id/show", DatabasesLive, :show
      live "/dashboards", DashboardsLive, :index
      live "/dashboards/:id/show", DashboardsLive, :show
      live "/monitors", MonitorsLive, :index
      live "/monitors/:id/show", MonitorsLive, :show
    end
  end

  scope "/admin" do
    pipe_through [:admin_browser, :require_authenticated_user]

    forward "/oban", TrifleWeb.ObanDashboardRouter
  end

  forward "/", TrifleApp.Router
end
