# ExampleJsonParse

This app parses a product catalog JSON output from Contentful CMS taken from https://github.com/contentful/content-models.

At first, it builds a nested `JsonReply.ProductCatalog` struct with the shape matching the JSON file. Then the app assembles a list of `Core.Product` structs from the product catalog. The latter list is an example of a different nested struct shape that can be suitable for the app's business logic.

The Domo generated callbacks `ensure_type_ok/1` and `new!/1` are used to validate structs conforming to their types and preconditions. F.e., one of the preconditions is for `valid_uri()` user type referencing `URI` that is required to have both `host` and `path` fields specified.

## Give it a try 

With `iex -S mix`:

Run `ExampleJsonParse.parse_valid_file()` to see parsed and valid struct built from JSON.

Run `ExampleJsonParse.parse_invalid_file()` to see the index where the malformed object is located in `product-catalog-invalid.json`.
