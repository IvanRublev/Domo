defmodule BenchmarkEctoDomo.Repo do
  use Ecto.Repo,
    otp_app: :benchmark_ecto_domo,
    adapter: Ecto.Adapters.Postgres
end
