defmodule JsonReply.ProductCatalog do
  @moduledoc false

  use Domo

  alias JsonReply.ProductCatalog.{
    ImageAsset,
    ProductEntry
  }

  defstruct image_assets: [%ImageAsset{}], product_entries: [%ProductEntry{}]

  @type t :: %__MODULE__{
          image_assets: [ImageAsset.t()],
          product_entries: [ProductEntry.t()]
        }

  defimpl MapShaper.Target do
    def translate_source_map(_value, map) do
      {:ok, product_entries} = ExJSONPath.eval(map, "$.entries[?(@.sys.contentType.sys.id == 'product')]")
      {:ok, image_assets} = ExJSONPath.eval(map, "$.assets[?(@.sys.type == 'Asset')]")

      %{"image_assets" => image_assets, "product_entries" => product_entries}
    end
  end
end
