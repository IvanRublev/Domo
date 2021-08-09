defmodule ExampleAvialia.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      ExampleAvialia.BoardingsRepo,
      ExampleAvialia.CargosRepo,
      # Start the PubSub system
      {Phoenix.PubSub, name: ExampleAvialia.PubSub},
      # Start the Endpoint (http/https)
      ExampleAvialiaWeb.Endpoint
      # Start a worker by calling: ExampleAvialia.Worker.start_link(arg)
      # {ExampleAvialia.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExampleAvialia.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    ExampleAvialiaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
