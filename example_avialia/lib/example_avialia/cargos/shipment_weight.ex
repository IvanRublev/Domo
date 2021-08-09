defmodule ExampleAvialia.Cargos.ShipmentWeight do
  use ExampleAvialia.TaggedTupleEctoType

  @type value :: units() | kilograms()

  @type units :: {:units, boxes() | big_bags() | barrels()}
  @type kilograms :: {:kilograms, pos_integer()}

  @type boxes :: {:boxes, pos_integer()}
  @type big_bags :: {:big_bags, pos_integer()}
  @type barrels :: {:barrels, pos_integer()}

  def all_units do
    [
      {:kilograms, 0},
      {:units, {:boxes, 0}},
      {:units, {:big_bags, 0}},
      {:units, {:barrels, 0}}
    ]
    |> Enum.map(&get_measurement/1)
  end

  def get_measurement(weight) do
    weight
    |> TaggedTuple.to_list()
    |> List.delete_at(-1)
    |> Enum.join("|")
  end

  def get_count(weight) do
    {_tag, count} = TaggedTuple.split(weight)
    count
  end

  def build(measurement_string, count) do
    tag =
      measurement_string
      |> String.split("|", trim: true)
      |> Enum.map(&String.to_existing_atom/1)
      |> TaggedTuple.from_list()

    TaggedTuple.tag(count, tag)
  end

  def to_kilograms!(weight, reference) do
    measurement = get_measurement(weight)
    kilos_per_count = Map.fetch!(reference, measurement)
    count = get_count(weight)
    count * kilos_per_count
  end
end
