# credo:disable-for-this-file
defmodule CustomStructUsingDomoOptionalField do
  use Domo

  defstruct(title: "some_title", subtitle: "", age: nil)

  @type t :: %__MODULE__{
          title: String.t(),
          subtitle: String.t(),
          age: integer() | nil
        }

  def env, do: __ENV__
end
