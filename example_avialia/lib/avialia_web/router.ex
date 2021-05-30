defmodule AvialiaWeb.Router do
  use AvialiaWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AvialiaWeb do
    pipe_through :browser

    get "/", PageController, :index
    post "/new_boarding", PageController, :new_boarding
    get "/delete_boarding", PageController, :delete_boarding
    post "/new_cargo", PageController, :new_cargo
    get "/delete_cargo", PageController, :delete_cargo
  end
end
