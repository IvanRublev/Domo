# credo:disable-for-this-file
defmodule Recipient do
  use Domo, skip_defaults: true

  @enforce_keys [:title, :name]
  defstruct [:title, :name, age: 0]

  @type title :: :mr | :ms | :dr
  @type name :: String.t()
  @type age :: integer
  @type t :: %__MODULE__{title: title(), name: name(), age: age()}
end

defmodule RecipientWarnOverriden do
  use Domo, skip_defaults: true, unexpected_type_error_as_warning: true

  @enforce_keys [:title, :name]
  defstruct [:title, :name, age: 0]

  @type title :: :mr | :ms | :dr
  @type name :: String.t()
  @type age :: integer
  @type t :: %__MODULE__{title: title(), name: name(), age: age()}
end

defmodule RecipientNewOverriden do
  use Domo, skip_defaults: true, name_of_new_function: :locally_set_new!

  @enforce_keys [:title, :name]
  defstruct [:title, :name, age: 0]

  @type title :: :mr | :ms | :dr
  @type name :: String.t()
  @type age :: integer
  @type t :: %__MODULE__{title: title(), name: name(), age: age()}
end

defmodule RecipientNestedOrTypes do
  use Domo, skip_defaults: true

  @enforce_keys [:title]
  defstruct @enforce_keys

  @type title :: :mr | Recipient.t() | :dr
  @type t :: %__MODULE__{title: title()}
end
