defmodule BotchiniWeb.Router do
  use BotchiniWeb, :router

  import BotchiniWeb.Auth, only: [require_user: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BotchiniWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :logged_in do
    plug :require_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :xml_api do
    plug :accepts, ["xml"]
  end

  scope "/", BotchiniWeb do
    pipe_through :browser

    get "/", PageController, :home

    get "/auth/login", AuthController, :login
    get "/auth/discord", AuthController, :discord
    get "/auth/discord/callback", AuthController, :callback
    get "/auth/return", AuthController, :return

    # Broadcasters get in with the key of their link instead
    live_session :broadcast, layout: {BotchiniWeb.Layouts, :screen} do
      live "/screens/:id/broadcast", ScreenLive.Broadcast
    end
  end

  scope "/", BotchiniWeb do
    pipe_through [:browser, :logged_in]

    live_session :watch,
      layout: {BotchiniWeb.Layouts, :screen},
      on_mount: {BotchiniWeb.Auth, :require_user} do
      live "/screens", ScreenLive.Guild
      live "/screens/:id", ScreenLive.Watch
    end
  end

  scope "/api", BotchiniWeb do
    pipe_through :api

    get "/status", StatusController, :index

    post "/twitch/webhooks/callback", TwitchController, :callback
    get "/youtube/webhooks/callback", YoutubeController, :challenge
  end

  scope "/api/whip", BotchiniWeb do
    post "/", WhipController, :create
    patch "/:room_id/:session_id", WhipController, :update
    delete "/:room_id/:session_id", WhipController, :delete
  end

  scope "/api", BotchiniWeb do
    pipe_through :xml_api

    post "/youtube/webhooks/callback", YoutubeController, :notification
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:botchini, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BotchiniWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
