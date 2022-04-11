# credo:disable-for-this-file
defmodule RecipientWithPrecond do
  use Domo, skip_defaults: true

  @enforce_keys [:title, :name]
  defstruct [:title, :name, age: 0]

  @type title :: :mr | :ms | :dr
  @type name :: String.t()

  @type age :: integer
  precond age: &(&1 < 300)

  @type t :: %__MODULE__{title: title(), name: name(), age: age()}
  precond t: &(String.length(&1.name) < 10)
end
