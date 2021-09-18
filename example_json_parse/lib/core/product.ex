defmodule Core.Product do
  @moduledoc false

  use Domo

  alias Core.Product.Image

  defstruct product_name: "",
            slug: "",
            image: nil,
            price: 0,
            tags: [],
            updated_at: ~N[2000-01-01 23:00:07]

  @type t :: %__MODULE__{
          product_name: String.t(),
          slug: String.t(),
          image: Image.t() | nil,
          price: non_neg_integer(),
          tags: [String.t()],
          updated_at: NaiveDateTime.t()
        }
end
