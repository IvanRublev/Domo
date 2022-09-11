# credo:disable-for-this-file
defmodule CustomStructUsingDomoOptionalField do
  use Domo

  defstruct title: "some_title", subtitle: "", age: nil, tracks: []

  @type t :: %__MODULE__{
          title: String.t(),
          subtitle: String.t(),
          age: integer() | nil,
          tracks: Ecto.Schema.has_many(atom())
        }

  def env, do: __ENV__
end
