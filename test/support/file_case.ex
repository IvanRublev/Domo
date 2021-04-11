defmodule PathHelpers do
  @moduledoc false
  def tmp_path() do
    Path.expand("../../../tmp", __DIR__)
  end

  def tmp_path(extra) do
    Path.join(tmp_path(), extra)
  end
end

defmodule Domo.FileCase do
  @moduledoc false
  use ExUnit.CaseTemplate
  import PathHelpers

  using do
    quote do
      import PathHelpers
    end
  end

  setup do
    File.mkdir_p!(tmp_path())
    on_exit(fn -> File.rm_rf(tmp_path()) end)
    :ok
  end
end
