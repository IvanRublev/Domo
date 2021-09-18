defmodule ExampleJsonParse do
  @moduledoc """
  Parses JSON and validates data to conform to model types.
  """

  alias Core.Product
  alias Core.Product.Image
  alias JsonReply.ProductCatalog

  def parse_valid_file do
    parse("product-catalog.json")
  end

  def parse_invalid_file do
    {:error, message} = parse("product-catalog-invalid.json")

    IO.puts("=== ERROR ===")
    Enum.each(message, fn {field, error} -> IO.puts("#{field}:\n#{error}") end)
  end

  defp parse(file_path) do
    binary = File.read!(file_path)

    with {:ok, map} <- Jason.decode(binary),
         catalog = MapShaper.from_map(%ProductCatalog{}, map, &maybe_remove_locale/1),
         {:ok, catalog} <- ProductCatalog.ensure_type_ok(catalog) do
      {:ok, to_products_list(catalog)}
    end
  end

  defp maybe_remove_locale(%{"en-US" => value}), do: value
  defp maybe_remove_locale(value), do: value

  defp to_products_list(%ProductCatalog{} = catalog) do
    image_by_id =
      catalog.image_assets
      |> Enum.group_by(& &1.id)
      |> Enum.map(fn {key, list} -> {key, list |> List.first() |> Map.drop([:id])} end)
      |> Enum.into(%{})

    Enum.map(catalog.product_entries, fn entry ->
      image = image_by_id[entry.image_asset_id]

      entry
      |> Map.from_struct()
      |> Map.drop([:image_asset_id])
      |> Map.put(:image, struct!(Image, Map.from_struct(image)))
      |> Product.new!()
    end)
  end
end
