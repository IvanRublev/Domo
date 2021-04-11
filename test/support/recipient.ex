# credo:disable-for-this-file
defmodule Recipient do
  use Domo

  @enforce_keys [:title, :name]
  defstruct [:title, :name, :age]

  @type title :: :mr | :ms | :dr
  @type name :: String.t()
  @type age :: integer
  @type t :: %__MODULE__{title: title(), name: name(), age: age()}
end

defmodule RecipientWarnOverriden do
  use Domo, unexpected_type_error_as_warning: true

  @enforce_keys [:title, :name]
  defstruct [:title, :name, :age]

  @type title :: :mr | :ms | :dr
  @type name :: String.t()
  @type age :: integer
  @type t :: %__MODULE__{title: title(), name: name(), age: age()}
end
