defmodule BenchmarkEctoDomo.Album do
  use TypedEctoSchema
  use Domo, ensure_struct_defaults: false

  import Ecto.Changeset
  import Domo.Changeset

  alias BenchmarkEctoDomo.MusicTypes
  alias BenchmarkEctoDomo.Track
  alias BenchmarkEctoDomo.Util.DateTimeGenerators

  @after_compile {BenchmarkEctoDomo.Util.TypesInspector, :inspect_types}

  typed_schema "albums" do
    field :title, :string, null: false
    field :artist, :string
    field(:studio, :string) :: MusicTypes.studio()
    field :release_date, :date, null: false
    field :single, :boolean, null: false
    field(:max_tracks_count, :integer, null: false) :: MusicTypes.tracks_count()

    has_many(:tracks, Track)

    timestamps()
  end

  def changeset(album, attrs) do
    album
    |> cast(attrs, __schema__(:fields))
    |> validate_type()
    |> cast_assoc(:tracks)
  end

  def changeset_ecto(album, attrs) do
    album
    |> cast(attrs, __schema__(:fields))
    |> validate_required([:title, :release_date, :single, :max_tracks_count])
    |> validate_inclusion(:studio, MusicTypes.studio_list())
    |> validate_acceptance(:single)
    |> validate_inclusion(:max_tracks_count, 1..29)
    |> cast_assoc(:tracks, with: &Track.changeset_ecto/2)
  end

  # Generate sample entities

  def sample(max_tracks_count) do
    StreamData.fixed_map(%{
      title: StreamData.string(:alphanumeric, length: 20),
      artist: StreamData.string(:alphanumeric, length: 15),
      studio: StreamData.member_of(["EMI", "CBS", "BMG", "PolyGram", "WEA", "MCA"]),
      release_date: DateTimeGenerators.date() |> StreamData.map(&to_string/1),
      single: StreamData.boolean() |> StreamData.map(&if(&1, do: "1", else: "0")),
      max_tracks_count: StreamData.constant(max_tracks_count) |> StreamData.map(&to_string/1),
      tracks: StreamData.list_of(Track.sample(Enum.random(1..max_tracks_count)), length: max_tracks_count)
    })
  end
end
