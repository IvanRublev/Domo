# Based on "Programming Ecto" example.
defmodule BenchmarkEctoDomo.Track do
  use TypedEctoSchema
  use Domo, ensure_struct_defaults: false

  import Ecto.Changeset
  import Domo.Changeset

  alias BenchmarkEctoDomo.Album
  alias BenchmarkEctoDomo.MusicTypes

  @after_compile {BenchmarkEctoDomo.Util.TypesInspector, :inspect_types}

  typed_schema "tracks" do
    field(:title, :string, null: false) :: MusicTypes.song_title()
    field(:duration, :integer) :: MusicTypes.song_duration()
    field(:index, :integer, null: false) :: non_neg_integer()
    field(:number_of_plays, :integer, null: false) :: non_neg_integer()
    timestamps()

    belongs_to(:album, Album)
  end

  def changeset(album, attrs) do
    album
    |> cast(attrs, __schema__(:fields))
    |> validate_type()
  end

  def changeset_ecto(track, attrs) do
    track
    |> cast(attrs, __schema__(:fields))
    |> validate_required([:title, :index, :number_of_plays])
    |> validate_length(:title, max: 25)
    |> validate_number(:duration, greater_than: 0, less_than_or_equal_to: 120)
    |> validate_number(:index, greater_than_or_equal_to: 0)
    |> validate_number(:number_of_plays, greater_than_or_equal_to: 0)
  end

  # Generate sample entities

  def sample(track_index) do
    StreamData.fixed_map(%{
      title: StreamData.string(:alphanumeric, length: 25),
      duration: StreamData.integer(5..85) |> StreamData.map(&to_string/1),
      index: StreamData.constant(track_index) |> StreamData.map(&to_string/1),
      number_of_plays: StreamData.integer(0..150) |> StreamData.map(&to_string/1)
    })
  end
end
