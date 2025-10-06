defmodule TrifleWeb.Router do
  use TrifleWeb, :router

  import TrifleWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {TrifleWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TrifleWeb do
    pipe_through :browser

    get "/home", PageController, :home_page
    get "/toc", PageController, :toc
    get "/privacy", PageController, :privacy
  end

  # Other scopes may use custom stacks.
  # scope "/api", TrifleWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:trifle, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TrifleWeb.Telemetry, ecto_repos: [Trifle.Repo]
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", TrifleWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{TrifleWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new

      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", TrifleWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{TrifleWeb.UserAuth, :ensure_authenticated}] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
    end
  end

  # TrifleApp routes mounted at root
  scope "/", TrifleApp do
    pipe_through [:browser, :require_authenticated_user]

    live_session :app_authenticated,
      on_mount: [{TrifleWeb.UserAuth, :ensure_authenticated}] do
      # Redirect root to dashboards
      live "/", AppRedirectLive, :index
      live "/projects", ProjectsLive, :index
      live "/projects/new", ProjectsLive, :new
      live "/projects/:id", TranspondersLive, :project_index
      live "/projects/:id/transponders", TranspondersLive, :project_index
      live "/projects/:id/transponders/new", TranspondersLive, :project_new
      live "/projects/:id/transponders/:transponder_id", TranspondersLive, :project_show
      live "/projects/:id/transponders/:transponder_id/edit", TranspondersLive, :project_edit
      live "/projects/:id/settings", ProjectSettingsLive
      live "/projects/:id/tokens", ProjectTokensLive, :index
      live "/projects/:id/tokens/new", ProjectTokensLive, :new
      live "/organization", OrganizationProfileLive, :show
      live "/organization/users", OrganizationUsersLive, :index
      live "/organization/billing", OrganizationBillingLive, :show
      live "/dbs", DatabasesLive, :index
      live "/dbs/new", DatabasesLive, :new
      # Database root redirects to Dashboards (handled by DatabaseRedirectLive)
      live "/dbs/:id", DatabaseRedirectLive, :index
      live "/dbs/:id/settings", DatabaseSettingsLive, :show
      # Explore (global) – select database via params
      live "/explore", ExploreLive, :show
      live "/dbs/:id/transponders", TranspondersLive, :database_index
      live "/dbs/:id/transponders/new", TranspondersLive, :database_new
      live "/dbs/:id/transponders/:transponder_id", TranspondersLive, :database_show
      live "/dbs/:id/transponders/:transponder_id/edit", TranspondersLive, :database_edit
      # Global Dashboards index (uses DashboardsLive)
      live "/dashboards", DashboardsLive, :index
      live "/dashboards/new", DashboardsLive, :new
      # Specific dashboard routes (standalone)
      live "/dashboards/:id", DashboardLive, :show
      live "/dashboards/:id/edit", DashboardLive, :edit
      live "/dashboards/:id/configure", DashboardLive, :configure
    end
  end

  # Export downloads (controller) under authenticated app scope
  scope "/", TrifleWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/export/dashboards/:id/pdf", ExportController, :dashboard_pdf
    get "/export/dashboards/:id/png", ExportController, :dashboard_png
    get "/export/dashboards/:id/csv", ExportController, :dashboard_csv
    get "/export/dashboards/:id/json", ExportController, :dashboard_json
  end

  scope "/", TrifleWeb do
    pipe_through [:browser]

    get "/invitations/:token", InvitationController, :show
    post "/invitations/:token/accept", InvitationController, :accept

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{TrifleWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end

  # Public dashboard access (no authentication required)
  scope "/d", TrifleApp do
    pipe_through [:browser]

    live_session :public_dashboard,
      on_mount: [{TrifleWeb.UserAuth, :mount_current_user}] do
      live "/:dashboard_id", DashboardLive, :public
    end
  end

  scope "/api", TrifleApi, as: :api do
    pipe_through(:api)

    get("/health", MetricsController, :health)
    post("/metrics", MetricsController, :create)
    get("/metrics", MetricsController, :index)
  end

  # Admin routes
  scope "/admin", TrifleAdmin, as: :admin do
    pipe_through [:browser, :require_authenticated_user]

    live_session :admin_authenticated,
      on_mount: [{TrifleWeb.UserAuth, :ensure_authenticated}] do
      live "/", AdminLive, :index
      live "/users", UsersLive, :index
      live "/databases", DatabasesLive, :index
      live "/databases/new", DatabasesLive, :new
      live "/databases/:id/edit", DatabasesLive, :edit
      live "/databases/:id/show", DatabasesLive, :show
    end
  end
end
