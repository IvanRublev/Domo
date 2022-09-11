# credo:disable-for-this-file
defmodule CustomStructImportingChangeset do
  use Domo, skip_defaults: true

  import Domo.Changeset

  defstruct [:title]

  @type t :: %__MODULE__{title: String.t()}

  def validate_type_imported? do
    validate_schemaless_type(%{}, __MODULE__, [])
  end
end
