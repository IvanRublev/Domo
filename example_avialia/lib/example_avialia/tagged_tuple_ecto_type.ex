defmodule ExampleAvialia.TaggedTupleEctoType do
  @moduledoc """
  Generates basic Ecto custom type for tagged tuple by adding required callbacks to using module.

  Stores tagged tuple as :map in the database.
  """
  defmacro __using__(_opts) do
    quote do
      use Ecto.Type

      @impl true
      def type, do: :map

      # We assume that client validates the value to conform to appropriate value() type
      # before dumping to the database. Because of that bypass value as is.
      @impl true
      def cast(value), do: {:ok, value}

      # When loading data from the database, as long as it's a map,
      # we just put the data back into a tagged tuple to be stored in
      # the loaded schema struct. No validation against value() type is performed at this point.
      # This is responsibility of the client receiving the schema struct.
      @impl true
      def load(map) when is_map(map) do
        tuple = TaggedTuple.from_map(map, &if(is_atom(&1), do: &1, else: String.to_existing_atom(&1)))

        {:ok, tuple}
      end

      # When dumping data to the database, we *expect* a tagged tuple of appropriate value() type.
      # This is responsibility of the client preparing schema to validate conformance to
      # the value() type.
      @impl true
      def dump(tagged_tuple) when is_tuple(tagged_tuple) do
        {:ok, TaggedTuple.to_map(tagged_tuple)}
      end
    end
  end
end
