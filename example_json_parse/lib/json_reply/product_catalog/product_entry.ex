defmodule JsonReply.ProductCatalog.ProductEntry do
  @moduledoc false

  use Domo

  alias JsonReply.ProductCatalog.ImageAsset

  defstruct product_name: "",
            slug: "",
            image_asset_id: ImageAsset.id_placeholder(),
            price: 0,
            tags: [],
            updated_at: ~N[2000-01-01 23:00:07]

  @type t :: %__MODULE__{
          product_name: String.t(),
          slug: String.t(),
          image_asset_id: ImageAsset.id(),
          price: non_neg_integer(),
          tags: [String.t()],
          updated_at: NaiveDateTime.t()
        }

  defimpl MapShaper.Target do
    def translate_source_map(_value, map) do
      updated_at =
        map
        |> get_in(["sys", "updatedAt"])
        |> NaiveDateTime.from_iso8601()
        |> then(fn {:ok, date_time} -> date_time end)

      fields =
        map
        |> Map.get("fields", %{})
        |> Map.take(["productName", "slug", "image", "price", "tags"])

      image_asset_id =
        fields
        |> ExJSONPath.eval("$.image['en-US'][0].sys.id")
        |> then(fn {:ok, list} -> list end)
        |> List.first()

      fields
      |> Map.put("updated_at", updated_at)
      |> Map.put("image_asset_id", image_asset_id)
    end
  end
end
