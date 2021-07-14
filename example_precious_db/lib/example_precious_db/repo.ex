defmodule ExamplePreciousDb.Repo do
  use Ecto.Repo,
    otp_app: :example_precious_db,
    adapter: Ecto.Adapters.Postgres
end
