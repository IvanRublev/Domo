defmodule BenchmarkEctoDomo do
  @moduledoc """
  Benchmarks the CPU and Memory consumption for Ecto insert operations
  with Ecto.Changeset validators and Domo `validate_type/2`.
  """

  alias BenchmarkEctoDomo.Album
  alias BenchmarkEctoDomo.Track
  alias Ecto.Type

  @inputs_count 3000

  @warmup_time_s 2
  @cpu_time_s 8
  @memory_time_s 2

  def run do
    inputs_table = album_inputs_table(@inputs_count, :albums_input)
    benchee(%{
      "Ecto.Changeset validate_.../1" => fn -> loop(fn -> Album.changeset_ecto(%Album{}, next_input_value(inputs_table, @inputs_count)) end) end,
      "Domo.Changeset validate_type/1" => fn -> loop(fn -> Album.changeset(%Album{}, next_input_value(inputs_table, @inputs_count)) end) end,
      "Domo Album.new!/1" => fn ->
        loop(fn ->
          {track_maps, album_map} = Map.pop!(next_input_value(inputs_table, @inputs_count), :tracks)
          tracks = Enum.map(track_maps, &Track.new!(cast_fields(Track, &1)))
          Album |> cast_fields(album_map) |> Map.put(:tracks, tracks) |> Album.new!()
        end)
      end
    })
    :ok
  end

  defp cast_fields(module, map) do
    for {key, value} <- map, into: %{}, do: {
      key,
      elem({:ok, _value} = Type.cast(module.__schema__(:type, key), value), 1)
    }
  end

  defp album_inputs_table(count, input_name) do
    puts_title("Generating #{count} inputs, may take a while.")
    albums = Album.sample(7) |> Enum.take(count)
    inputs_table = init_input(input_name, albums, count)
    puts_title("Generated #{count} album inputs.")
    inputs_table
  end

  defp puts_title(title) do
    IO.puts("")
    IO.puts(title)
    IO.puts("=========================================")
  end

  defp init_input(name, values, max_position) do
    input_table = :ets.new(name, [:set, :public])

    values_tuple =
      values
      |> List.to_tuple()
      |> Tuple.insert_at(0, :values)

    :ets.insert(input_table, values_tuple)
    :ets.insert(input_table, {:position, max_position + 1})
    input_table
  end

  defp next_input_value(input_table, max_position) do
    position = :ets.update_counter(input_table, :position, {2, -1, 1, max_position})
    :ets.lookup_element(input_table, :values, position + 1)
  end

  defp benchee(plan) do
    Benchee.run(plan, warmup: @warmup_time_s, time: @cpu_time_s, memory_time: @memory_time_s)
  end

  defp loop(fun) do
    # this makes the execution time close to 1ms
    Enum.each(1..3000, fn _ -> fun.() end)
  end
end
