defmodule TrifleApp.Router do
  use TrifleApp, :router

  import TrifleApp.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {TrifleApp.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :projects_enabled do
    plug TrifleApp.Plugs.RequireProjectsEnabled
  end

  pipeline :projects_api_enabled do
    plug TrifleApp.Plugs.RequireProjectsEnabled, format: :json
  end

  scope "/", TrifleApp do
    pipe_through :browser

    get "/home", PageController, :home_page
    get "/toc", PageController, :toc
    get "/privacy", PageController, :privacy
  end

  scope "/auth", TrifleApp do
    pipe_through [:browser]

    get "/:provider", GoogleAuthController, :request
    get "/:provider/callback", GoogleAuthController, :callback
    post "/:provider/callback", GoogleAuthController, :callback
  end

  if Application.compile_env(:trifle, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TrifleWeb.Telemetry, ecto_repos: [Trifle.Repo]
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  scope "/", TrifleApp do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{TrifleApp.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", TrifleApp do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{TrifleApp.UserAuth, :ensure_authenticated}] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
    end
  end

  scope "/", TrifleApp do
    pipe_through [:browser, :require_authenticated_user]

    live_session :app_authenticated,
      on_mount: [{TrifleApp.UserAuth, :ensure_authenticated}] do
      live "/", AppRedirectLive, :index
      live "/organization", OrganizationRedirectLive, :index
      live "/organization/profile", OrganizationProfileLive, :show
      live "/organization/users", OrganizationUsersLive, :index
      live "/organization/sso", OrganizationSSOLive, :show
      live "/organization/delivery", OrganizationDeliveryLive, :show
      live "/organization/billing", OrganizationBillingLive, :show
      live "/dbs", DatabasesLive, :index
      live "/dbs/new", DatabasesLive, :new
      live "/dbs/:id", DatabaseRedirectLive, :index
      live "/dbs/:id/settings", DatabaseSettingsLive, :show
      live "/explore", ExploreLive, :show
      live "/explore/v2", ExploreV2Live, :show
      live "/dbs/:id/transponders", DatabaseTranspondersLive, :index
      live "/dbs/:id/transponders/new", DatabaseTranspondersLive, :new
      live "/dbs/:id/transponders/:transponder_id", DatabaseTranspondersLive, :show
      live "/dbs/:id/transponders/:transponder_id/edit", DatabaseTranspondersLive, :edit
      live "/dashboards", DashboardsLive, :index
      live "/dashboards/new", DashboardsLive, :new
      live "/dashboards/:id", DashboardLive, :show
      live "/dashboards/:id/configure", DashboardLive, :configure
      live "/monitors", MonitorsLive, :index
      live "/monitors/new", MonitorsLive, :new
      live "/monitors/:id", MonitorLive, :show
      live "/monitors/:id/configure", MonitorLive, :configure
      live "/chat", ChatLive, :show
    end

    get "/integrations/slack/oauth/callback", Integrations.SlackController, :callback
  end

  scope "/", TrifleApp do
    pipe_through [:browser, :require_authenticated_user, :projects_enabled]

    live_session :app_authenticated_projects,
      on_mount: [{TrifleApp.UserAuth, :ensure_authenticated}] do
      live "/projects", ProjectsLive, :index
      live "/projects/new", ProjectsLive, :new
      live "/projects/:id", ProjectRedirectLive, :index
      live "/projects/:id/transponders", ProjectTranspondersLive, :index
      live "/projects/:id/transponders/new", ProjectTranspondersLive, :new
      live "/projects/:id/transponders/:transponder_id", ProjectTranspondersLive, :show
      live "/projects/:id/transponders/:transponder_id/edit", ProjectTranspondersLive, :edit
      live "/projects/:id/settings", ProjectSettingsLive
      live "/projects/:id/tokens", ProjectTokensLive, :index
      live "/projects/:id/tokens/new", ProjectTokensLive, :new
    end
  end

  scope "/", TrifleApp do
    pipe_through [:browser, :require_authenticated_user]

    get "/export/dashboards/:id/pdf", ExportController, :dashboard_pdf
    get "/export/dashboards/:id/png", ExportController, :dashboard_png
    get "/export/dashboards/:id/widgets/:widget_id/pdf", ExportController, :dashboard_widget_pdf
    get "/export/dashboards/:id/widgets/:widget_id/png", ExportController, :dashboard_widget_png
    get "/export/dashboards/:id/csv", ExportController, :dashboard_csv
    get "/export/dashboards/:id/json", ExportController, :dashboard_json
    get "/export/monitors/:id/pdf", ExportController, :monitor_pdf
    get "/export/monitors/:id/png", ExportController, :monitor_png
    get "/export/monitors/:id/widgets/:widget_id/pdf", ExportController, :monitor_widget_pdf
    get "/export/monitors/:id/widgets/:widget_id/png", ExportController, :monitor_widget_png
  end

  scope "/", TrifleApp do
    pipe_through [:browser]

    get "/invitations/:token", InvitationController, :show
    post "/invitations/:token/accept", InvitationController, :accept
    live "/export/layouts/:token", ExportLayoutLive, :show

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{TrifleApp.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end

  scope "/d", TrifleApp do
    pipe_through [:browser]

    live_session :public_dashboard,
      on_mount: [{TrifleApp.UserAuth, :mount_current_user}] do
      live "/:dashboard_id", DashboardPublicLive, :public
    end
  end

  scope "/api", TrifleApi, as: :api do
    pipe_through [:api]

    get("/health", MetricsController, :health)

    scope "/" do
      pipe_through [:projects_api_enabled]

      post("/metrics", MetricsController, :create)
      get("/metrics", MetricsController, :index)
    end
  end
end
