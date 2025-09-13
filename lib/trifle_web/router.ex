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

    get "/", PageController, :home
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
      # Registration route - conditionally enabled via REGISTRATION_ENABLED environment variable
      if TrifleWeb.RegistrationConfig.enabled?() do
        live "/users/register", UserRegistrationLive, :new
      end
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

  # TrifleApp routes
  scope "/app", TrifleApp do
    pipe_through [:browser, :require_authenticated_user]

    live_session :app_authenticated,
      on_mount: [{TrifleWeb.UserAuth, :ensure_authenticated}] do
      live "/", AppLive, :dashboard
      live "/projects", ProjectsLive, :index
      live "/projects/new", ProjectsLive, :new
      live "/projects/:id", ProjectLive, :show
      live "/projects/:id/transponders", ProjectTranspondersLive
      live "/projects/:id/settings", ProjectSettingsLive
      live "/projects/:id/tokens", ProjectTokensLive, :index
      live "/projects/:id/tokens/new", ProjectTokensLive, :new
      live "/dbs", DatabasesLive, :index
      # Database root redirects to Dashboards (handled by DatabaseRedirectLive)
      live "/dbs/:id", DatabaseRedirectLive, :index
      # Explore tab explicit route
      live "/dbs/:id/explore", DatabaseExploreLive, :show
      live "/dbs/:id/transponders", DatabaseTranspondersLive, :index
      live "/dbs/:id/transponders/new", DatabaseTranspondersLive, :new
      live "/dbs/:id/transponders/:transponder_id", DatabaseTranspondersLive, :show
      live "/dbs/:id/transponders/:transponder_id/edit", DatabaseTranspondersLive, :edit
      live "/dbs/:id/dashboards", DatabaseDashboardsLive, :index
      live "/dbs/:id/dashboards/new", DatabaseDashboardsLive, :new
      live "/dbs/:id/dashboards/:dashboard_id", DatabaseDashboardLive, :show
      live "/dbs/:id/dashboards/:dashboard_id/edit", DatabaseDashboardLive, :edit
      live "/dbs/:id/dashboards/:dashboard_id/configure", DatabaseDashboardLive, :configure
    end
  end

  scope "/", TrifleWeb do
    pipe_through [:browser]

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
      live "/:dashboard_id", DatabaseDashboardLive, :public
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
