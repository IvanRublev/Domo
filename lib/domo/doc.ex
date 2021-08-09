defmodule Domo.Doc do
  @moduledoc false

  def readme_doc(comment) do
    "README.md"
    |> File.read!()
    |> String.split("#{comment}\n")
    |> Enum.at(1)
    |> String.trim("\n")
  end
end
