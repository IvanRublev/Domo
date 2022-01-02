defmodule Benchmark do
  @moduledoc """
  Benchmarks the CPU and Memory consumption for struct operations
  with type checking comparing to native ones.
  """

  alias Benchmark.{Inputs, Samples, Tweet}

  @warmup_time_s 2
  @cpu_time_s 8
  @memory_time_s 2

  def run do
    count = 3_000
    puts_title("Generating #{count} inputs, may take a while.")

    {tweet_maps, user_maps} =
      [Samples.tweet_map(), Samples.user_map()]
      |> Stream.zip()
      |> Enum.take(count)
      |> Enum.unzip()

    count = length(tweet_maps)
    tweets_approx_size_kb = :erlang.term_to_binary(tweet_maps) |> byte_size() |> Kernel.*(2) |> div(3) |> div(1024)
    users_approx_size_kb = :erlang.term_to_binary(user_maps) |> byte_size() |> Kernel.*(2) |> div(3) |> div(1024)

    tweet_maps_input1 = init_input(:tweet_maps1, tweet_maps, count)
    tweet_maps_input2 = init_input(:tweet_maps2, tweet_maps, count)

    tweets = Enum.map(tweet_maps, &Tweet.new!/1)
    tweets_input1 = init_input(:tweet_maps1, tweets, count)
    tweets_input2 = init_input(:tweet_maps2, tweets, count)

    users = Enum.map(user_maps, &Tweet.User.new!/1)
    users_input1 = init_input(:users1, users, count)
    users_input2 = init_input(:users2, users, count)

    puts_title("""
    Generated #{count} tweet inputs with summary approx. size of #{tweets_approx_size_kb}KB.
    Generated #{count} user inputs with summary approx. size of #{users_approx_size_kb}KB.\
    """)

    for {title, fun} <- [
          {"struct's construction",
           fn ->
             benchee(%{
               "__MODULE__.new!(map)" => fn -> loop(fn -> Tweet.new!(next_random_value(tweet_maps_input1, count)) end) end,
               "struct!(__MODULE__, map)" => fn -> loop(fn -> struct!(Tweet, next_random_value(tweet_maps_input2, count)) end) end
             })
           end},
          {"struct's field modification",
           fn ->
             benchee(%{
               "struct!(tweet, user: user) |> __MODULE__.ensure_type!()" => fn ->
                 loop(fn ->
                   struct!(next_random_value(tweets_input1, count), user: next_random_value(users_input1, count)) |> Tweet.ensure_type!()
                 end)
               end,
               "struct!(tweet, user: user)" => fn ->
                 loop(fn ->
                   struct!(next_random_value(tweets_input1, count), user: next_random_value(users_input1, count))
                 end)
               end
             })
           end}
        ] do
      puts_title("Benchmark #{title}")
      fun.()
    end
  end

  def puts_title(title) do
    IO.puts("")
    IO.puts(title)
    IO.puts("=========================================")
  end

  def init_input(name, values, max_position) do
    input_table = :ets.new(name, [:set, :public])

    values_tuple =
      values
      |> List.to_tuple()
      |> Tuple.insert_at(0, :values)

    :ets.insert(input_table, values_tuple)
    :ets.insert(input_table, {:position, max_position + 1})
    input_table
  end

  def next_random_value(input_table, max_position) do
    position = :ets.update_counter(input_table, :position, {2, -1, 1, max_position})
    :ets.lookup_element(input_table, :values, position + 1)
  end

  def benchee(plan) do
    Benchee.run(plan, warmup: @warmup_time_s, time: @cpu_time_s, memory_time: @memory_time_s)
  end

  def loop(fun) do
    # this makes the execution time close to 1ms
    Enum.each(1..2000, fn _ -> fun.() end)
  end
end
