defmodule AppWeb.Router do
  use AppWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AppWeb do
    pipe_through :api

    get "/", OrderController, :index
    post "/ping", OrderController, :ping
    post "/add_order", OrderController, :add_order
    get "/all", OrderController, :all
    post "/kilogrammize", OrderController, :kilogrammize
  end
end
