# Script for populating the database. You can run it as:
#
#     mix run priv/cargos_repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     ExampleAvialia.BoardingsRepo.insert!(%ExampleAvialia.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

require Ecto.Query

alias ExampleAvialia.CargosRepo, as: Repo

Repo.query("TRUNCATE #{ExampleAvialia.Cargos.Measurement.__schema__(:source)} CASCADE")

now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

measurements =
  [
    %{name: "kilograms", kilos: 1},
    %{name: "units|boxes", kilos: 50},
    %{name: "units|big_bags", kilos: 25},
    %{name: "units|barrels", kilos: 137}
  ]
  |> Enum.map(&Map.merge(&1, %{inserted_at: now, updated_at: now}))

Repo.insert_all(ExampleAvialia.Cargos.Measurement, measurements)
