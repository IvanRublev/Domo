defmodule JsonReply.ProductCatalog.ImageAsset do
  @moduledoc false

  use Domo

  alias Core.Product.Image

  @id_placeholder "000000000000000000000"
  def id_placeholder, do: @id_placeholder

  defstruct id: @id_placeholder,
            uri: Image.valid_uri_placeholder(),
            byte_size: 0,
            dimensions: {0, 0}

  @type t :: %__MODULE__{
          id: id(),
          uri: Image.valid_uri(),
          byte_size: non_neg_integer(),
          dimensions: {non_neg_integer(), non_neg_integer()}
        }

  @type id :: String.t()
  precond id: fn value ->
            bs = byte_size(value)
            20 < bs and bs < 23
          end

  defimpl MapShaper.Target do
    def translate_source_map(_value, map) do
      file =
        map
        |> ExJSONPath.eval("$.fields.file['en-US']")
        |> then(fn {:ok, list} -> list end)
        |> List.first() || %{}

      id =
        map
        |> ExJSONPath.eval("$.sys.id")
        |> then(fn {:ok, list} -> list end)
        |> List.first()

      dimensions = {
        get_in(file, ["details", "image", "width"]) || 0,
        get_in(file, ["details", "image", "height"]) || 0
      }

      byte_size = get_in(file, ["details", "size"]) || 0

      uri =
        file
        |> Map.get("url")
        |> URI.parse()

      %{"id" => id, "uri" => uri, "byte_size" => byte_size, "dimensions" => dimensions}
    end
  end
end
