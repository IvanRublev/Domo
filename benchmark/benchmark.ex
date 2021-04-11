defmodule Benchmark do
  @moduledoc """
  Benchmarks the CPU and Memory consumption for struct operations
  with type checking comparing to native ones.
  """

  alias Benchmark.{Inputs, Samples, Tweet}

  def run do
    count = 10_000
    puts_title("Generate #{count} inputs, may take a while.")

    list = Enum.take(Stream.zip(Samples.tweet_map(), Samples.user_map()), count)
    {:ok, maps_pid} = Inputs.start_link(list)

    tweet_user_list =
      Enum.map(list, fn {tweet_map, user_map} ->
        {struct(Tweet, Map.put(tweet_map, :user, nil)), struct(Tweet.User, user_map)}
      end)

    {:ok, tweet_user_pid} = Inputs.start_link(tweet_user_list)

    for {title, fun} <- [
          {"Construction of a struct", fn -> bench_construction(maps_pid) end},
          {"A struct's field modification", fn -> bench_put(tweet_user_pid) end}
        ] do
      puts_title(title)
      fun.()
    end
  end

  def puts_title(title) do
    IO.puts("")
    IO.puts(title)
    IO.puts("=========================================")
  end

  defp bench_construction(pid) do
    Benchee.run(%{
      "__MODULE__.new(arg)" => fn ->
        {tweet_map, user_map} = Inputs.next_input(pid)
        Tweet.new(Map.merge(tweet_map, %{user: Tweet.User.new(user_map)}))
      end,
      "struct!(__MODULE__, arg)" => fn ->
        {tweet_map, user_map} = Inputs.next_input(pid)
        struct!(Tweet, Map.merge(tweet_map, %{user: struct!(Tweet.User, user_map)}))
      end
    })
  end

  defp bench_put(pid) do
    Benchee.run(%{
      "%{tweet | user: arg} |> __MODULE__.ensure_type!()" => fn ->
        {tweet, user} = Inputs.next_input(pid)
        %{tweet | user: user} |> Tweet.ensure_type!()
      end,
      "struct!(tweet, user: arg)" => fn ->
        {tweet, user} = Inputs.next_input(pid)
        struct!(tweet, user: user)
      end
    })
  end
end

defmodule Benchmark.Inputs do
  use GenServer

  def start_link(inputs) do
    GenServer.start_link(__MODULE__, inputs)
  end

  def next_input(pid) do
    GenServer.call(pid, :next_input)
  end

  @impl true
  def init(list) when is_list(list) do
    {:ok, {0, Enum.count(list), list}}
  end

  @impl true
  def handle_call(:next_input, _caller, {idx, count, inputs}) do
    new_idx = idx + 1

    state = {
      if(new_idx == count, do: 0, else: new_idx),
      count,
      inputs
    }

    {:reply, Enum.at(inputs, idx), state}
  end
end
