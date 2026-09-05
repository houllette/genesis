defmodule GenesisWeb.Router do
  use GenesisWeb, :router

  import GenesisWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GenesisWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; connect-src 'self' ws: wss:"
    }

    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", GenesisWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", GenesisWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:genesis, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: GenesisWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", GenesisWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{GenesisWeb.UserAuth, :require_authenticated}] do
      live "/worlds", WorldLibraryLive, :index
      live "/worlds/:world_id", WorkspaceLive, :world
      live "/worlds/:world_id/atlas", AtlasLive, :index
      live "/worlds/:world_id/places/:zone_id", WorkspaceLive, :zone
      live "/worlds/:world_id/places/:zone_id/resources", SettlementLive, :edit
      live "/worlds/:world_id/campaigns/:campaign_id", WorkspaceLive, :campaign
      live "/worlds/:world_id/experiences/:experience_id", WorkspaceLive, :experience
      live "/worlds/:world_id/experiences/:experience_id/resources", SettlementLive, :run
      live "/invitations/:token", InvitationLive, :accept
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", GenesisWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{GenesisWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
