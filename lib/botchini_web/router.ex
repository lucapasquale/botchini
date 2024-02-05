defmodule BotchiniWeb.Router do
  use BotchiniWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BotchiniWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # pipeline :xml_api do
  #   plug :accepts, ["xml"]
  # end

  scope "/", BotchiniWeb do
    pipe_through :browser

    get "/", PageController, :index
  end

  scope "/api", BotchiniWeb do
    pipe_through :api

    get "/status", Api.StatusController, :index

    post "/twitch/webhooks/callback", Api.TwitchController, :callback
    get "/youtube/webhooks/callback", Api.YoutubeController, :challenge
  end

  # scope "/api", BotchiniWeb do
  #   pipe_through :xml_api

  #   post "/youtube/webhooks/callback", YoutubeController, :notification
  # end

  # Other scopes may use custom stacks.
  # scope "/api", BotchiniWeb do
  #   pipe_through :api
  # end

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
