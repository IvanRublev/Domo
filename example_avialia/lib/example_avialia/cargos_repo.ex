defmodule ExampleAvialia.CargosRepo do
  use Ecto.Repo,
    otp_app: :example_avialia,
    adapter: Ecto.Adapters.Postgres
end
