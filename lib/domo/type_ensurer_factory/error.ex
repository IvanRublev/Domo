defmodule Domo.TypeEnsurerFactory.Error do
  @moduledoc false

  defstruct [:compiler_module, :file, :struct_module, :message]

  @typedoc "Struct for Domo compilation error."
  @type t :: %__MODULE__{
          compiler_module: module,
          file: String.t(),
          struct_module: module | nil,
          message: tuple | atom
        }
end
