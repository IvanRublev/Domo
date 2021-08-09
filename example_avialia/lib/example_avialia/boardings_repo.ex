defmodule ExampleAvialia.BoardingsRepo do
  use Ecto.Repo,
    otp_app: :example_avialia,
    adapter: Ecto.Adapters.Postgres
end
