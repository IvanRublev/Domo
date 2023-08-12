# credo:disable-for-this-file
# This module simulates an Ecto.Schema with reflection functions by convention https://hexdocs.pm/ecto/Ecto.Schema.html#module-reflection
defmodule EctoSchemaErsatz do
  defstruct([:assoc_items, :embed_items])

  def __schema__(:associations), do: [:assoc_items]
  def __schema__(:embeds), do: [:embed_items]
end
