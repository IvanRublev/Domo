# From https://gist.github.com/LostKobrakai/7137eb20ed59fc8c6af0e94331cf470c#file-date_time_generators_streamdata-ex
defmodule BenchmarkEctoDomo.Util.DateTimeGenerators do
  import StreamData

  @time_zones ["Etc/UTC"]

  def date do
    tuple({integer(1970..2050), integer(1..12), integer(1..31)})
    |> bind_filter(fn tuple ->
      case Date.from_erl(tuple) do
        {:ok, date} -> {:cont, constant(date)}
        _ -> :skip
      end
    end)
  end

  def time do
    tuple({integer(0..23), integer(0..59), integer(0..59)})
    |> map(&Time.from_erl!/1)
  end

  def naive_datetime do
    tuple({date(), time()})
    |> map(fn {date, time} ->
      {:ok, naive_datetime} = NaiveDateTime.new(date, time)
      naive_datetime
    end)
  end

  def datetime do
    tuple({naive_datetime(), member_of(@time_zones)})
    |> map(fn {naive_datetime, time_zone} ->
      DateTime.from_naive!(naive_datetime, time_zone)
    end)
  end
end
