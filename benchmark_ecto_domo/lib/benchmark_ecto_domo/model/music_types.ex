defmodule BenchmarkEctoDomo.MusicTypes do
  @moduledoc """
  Module with Music related types
  """
  import Domo

  @studio_list ["EMI", "CBS", "BMG", "PolyGram", "WEA", "MCA"]

  @type studio :: String.t()
  precond studio: & &1 in @studio_list

  @type tracks_count :: integer()
  precond tracks_count: &(1 <= &1 and &1 <= 29)

  @type song_title :: String.t()
  precond song_title: &String.length(&1) <= 25

  @type song_duration :: pos_integer()
  precond song_duration: &(&1 <= 120)

  def studio_list, do: @studio_list
end
