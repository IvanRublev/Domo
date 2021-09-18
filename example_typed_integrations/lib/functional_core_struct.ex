defmodule FunctionalCoreStruct do
  @moduledoc """
  Struct is defined with a combination of [TypedStruct](https://github.com/ejpcmac/typed_struct)
  and [Domo](https://github.com/IvanRublev/Domo).

  It automatically validates default values during the compile-time unless the
  `ensure_struct_defaults: false` flag is given to Domo.

  F.e. change the `:name` field's default value to `:invalid` in this file,
  and recompile the project. The compilation should fail because of the wrong type.

  Or make the `:name` field's default value longer than 10 characters.
  Then the compilation should fail due to the precondition associated with `t()`.

  It validates the data during the runtime. See the list of appropriate functions
  at the end of the file.
  """

  use TypedStruct
  use Domo

  @type name :: String.t()
  precond name: &validate_required/1

  @type last_name :: String.t()
  precond last_name: &validate_required/1

  typedstruct enforce: true do
    field :name, name(), default: "Joe"
    field :last_name, last_name(), enforce: false
  end

  precond t: &validate_full_name/1

  defp validate_required(name) when byte_size(name) == 0, do: {:error, "can't be empty string"}
  defp validate_required(_name), do: :ok

  defp validate_full_name(struct) do
    if String.length(struct.name) + String.length(struct.last_name || "") > 10 do
      {:error, "Summary length of :name and :last_name can't be greater than 10 bytes."}
    else
      :ok
    end
  end

  # Functions added to this module by Domo:
  # new!
  # new_ok
  # ensure_type!
  # ensure_type_ok
  # typed_fields
  # required_fields
end
