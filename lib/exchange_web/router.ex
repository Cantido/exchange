defmodule ExchangeWeb.Router do
  use ExchangeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {ExchangeWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ExchangeWeb do
    pipe_through :browser

    resources "/symbols", SymbolController, except: [:show]
    live "/symbols/:id", DashboardLive, :index

  end

  scope "/api/v1", ExchangeWeb.API do
    pipe_through :api

    resources "/symbols", SymbolController do
      resources "/orders", OrderController, only: [:create]
    end
  end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser
      live_dashboard "/live-dashboard", metrics: ExchangeWeb.Telemetry
    end
  end
end
