defprotocol MapShaper do
  @moduledoc """
  Protocol to turn a map into nested structs.
  """

  @fallback_to_any true

  @doc """
  Function to translate JSON map to a structure or a list of structures given
  as the first argument.

  First argument defines the shape of nested structures like the following:
  `[%Post{comments: %Comment{author: %Author{}}}]`.

  The desired shape of nested structs can be also defined with the `defstruct/1`
  calls of appropriate modules, then the first argument of `from_map/3`
  can be shortened to `[%Post{}]`.

  Calls `post_process_fn` to map values that are not struct themselves
  before adding them to the struct.

  Define how to filter or translate JSON map keys into the struct fields
  by conforming the struct to `MapShaper.Target` protocol.

  To override the keys conversion rules conform the struct
  to `MapShaper.Target.Key` protocol.
  """
  def from_map(value, map, post_process_fn \\ & &1)

  defprotocol Target do
    @moduledoc false

    @fallback_to_any true

    @doc """
    Translates the JSON map to match the target struct fields.

    Should return a map with keys matching the fields of the struct.

    The `MapShaper.from_map/3` function will call this one to prepare the map
    before taking fields from it for building the structure.
    """
    def translate_source_map(value, map)

    defprotocol Key do
      @moduledoc false

      @fallback_to_any true

      @doc """
      Returns a list of keys for the given struct fields key.
      `from_map/3` uses the return value from this function to get first
      matching key from the JSON map that may have camel or underscore case keys.

      The default implementation returns the following list for :a_key input:
      of possible keys `[:a_key, "a_key", "AKey", "aKey"]`.
      """
      def key_variants(value, struct_key_atom)
    end
  end
end

defimpl MapShaper, for: Any do
  def from_map(_value, nil, _post_process_fn) do
    nil
  end

  def from_map([value], list, post_process_fn) when is_list(list) do
    Enum.map(list, &MapShaper.from_map(value, &1, post_process_fn))
  end

  def from_map([value], not_list, _post_process_fn) do
    raise "Call with the list shape [#{inspect(value)}] given as the first argument expects the list of maps as the second argument. Received instead: #{inspect(not_list)}"
  end

  def from_map(%struct_name{} = value, map, post_process_fn) do
    alias MapShaper.Target
    alias MapShaper.Target.Key

    map = Target.translate_source_map(value, map)

    fields =
      value
      |> Map.from_struct()
      |> Enum.reduce([], fn {struct_key, struct_value}, fields ->
        key_variants = Key.key_variants(value, struct_key)
        map_value = Enum.find_value(key_variants, &Map.get(map, &1))
        casted_value = MapShaper.from_map(struct_value, map_value, post_process_fn)
        [{struct_key, casted_value} | fields]
      end)

    struct!(struct_name, fields)
  end

  def from_map(_value, map, post_process_fn) do
    post_process_fn.(map)
  end
end

defimpl MapShaper.Target, for: Any do
  def translate_source_map(_value, map), do: map
end

defimpl MapShaper.Target.Key, for: Any do
  def key_variants(_value, struct_key_atom) do
    key_str = Atom.to_string(struct_key_atom)
    underscore_str = Macro.underscore(key_str)
    camel_str = Macro.camelize(key_str)

    first = String.slice(camel_str, 0..0) |> String.downcase()
    lf_camel_str = first <> String.slice(camel_str, 1..-1)

    [
      struct_key_atom,
      key_str,
      underscore_str,
      camel_str,
      lf_camel_str
    ]
  end
end
