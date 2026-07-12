defmodule BuisWeb.Router do
  use BuisWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BuisWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BuisWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", BuisWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:buis, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BuisWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    # Console CLI de test du back Ash (dev uniquement).
    scope "/cli", BuisWeb do
      pipe_through :browser

      live "/", CliLive.Menu
      live "/r/:resource/list/:action", CliLive.Subfile
      live "/r/:resource/a/:action", CliLive.Screen
      live "/r/:resource/a/:action/:id", CliLive.Screen
      get "/actor", CliActorController, :set
    end
  end
end
