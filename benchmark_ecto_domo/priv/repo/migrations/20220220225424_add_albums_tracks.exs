defmodule BenchmarkEctoDomo.Repo.Migrations.AddAlbumsTracks do
  use Ecto.Migration

  def change do
    create table(:albums) do
      add :title, :string, null: false
      add :artist, :string
      add :studio, :string
      add :release_date, :date, null: false
      add :max_tracks_count, :integer, null: false
      timestamps()
    end

    create table(:tracks) do
      add :title, :string, null: false
      add :duration, :integer, null: true
      add :index, :integer, null: false
      add :number_of_plays, :integer, null: false, default: 0
      add :album_id, references(:albums, on_delete: :nothing)
      timestamps()
    end

    create index(:tracks, :title)
    create index(:tracks, :album_id)
  end
end
