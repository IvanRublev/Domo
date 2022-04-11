defmodule EctoSchemaStruct do
  @moduledoc """
  Struct is defined with a combination of [TypedEctoSchema](https://github.com/bamorim/typed_ecto_schema)
  and [Domo](https://github.com/IvanRublev/Domo).

  The `enforce: true` given to TypedEctoSchema excludes default values from
  the struct.

  Domo automatically validates default values during the compile-time unless the
  `skip_defaults: true` flag is given.

  F.e. remove `default: "Joe"` option for the `:name` field in this file,
  and recompile the project. The compilation should fail because of `nil` that
  is not expected due to `enforce: true`.

  Or change the `:happy` field's default value to `nil`.
  Then the compilation should fail due to the precondition associated with `t()`.

  Or make the `:name` field's default value longer than 10 characters.
  Then the compilation should fail due to the precondition associated with `t()`.

  Domo and Domo.Changeset provides several helper functions for change set
  functions. See how they are used at the end of the file.
  """

  use TypedEctoSchema
  use Domo

  import Ecto.Changeset
  import Domo.Changeset

  @type name :: String.t()
  precond name: &validate_required/1

  @type last_name :: String.t()
  precond last_name: &validate_required/1

  typed_schema "people" do
    field(:name, :string, default: "Joe", null: false)
    field(:last_name, :string) :: last_name() | nil
    field(:age, :integer) :: non_neg_integer() | nil
    field(:happy, :boolean, default: true, null: false)
    field(:phone, :string)
    timestamps(type: :naive_datetime_usec)
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

  # See how the following functions by Domo used in `changeset/2` below:
  # typed_fields() - added to the struct's module
  # required_fields() - added to the struct's module
  # validate_type() - imported from Domo.Changeset

  def changeset(changeset, attrs) do
    changeset
    |> cast(attrs, typed_fields())
    |> validate_required(required_fields())
    |> validate_type()
  end
end
