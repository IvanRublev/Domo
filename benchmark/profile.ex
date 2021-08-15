defmodule Benchmark.Profile do
  @moduledoc "Module to profile functions that involves type checking"

  alias Benchmark.{Samples, Tweet}

  def run do
    profile_new()
  end

  def profile_new do
    count = 10_000
    Benchmark.puts_title("Generate #{count} inputs, may take a while.")
    list = Enum.take(Samples.user_map(), count)

    Benchmark.puts_title("Profile new/1")

    {:ok, pid} =
      Task.start(fn ->
        _ =
          Enum.map(list, fn user_map ->
            Tweet.User.new!(user_map)
          end)
      end)

    Profiler.profile(pid)
  end
end
