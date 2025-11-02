defmodule EctoSchemaStruct do
  @moduledoc """
  Struct is defined with a combination of [TypedEctoSchema](https://github.com/bamorim/typed_ecto_schema)
  and [Domo](https://github.com/IvanRublev/Domo).

  Domo automatically validates default values during the compile-time unless the
  `skip_defaults: true` flag is given.

  F.e. remove `default: "Joe"` option for the `:name` field in this file,
  and recompile the project. The compilation should fail because of `nil` that
  is not expected.

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
  precond name: &validate_part_name/1

  defp validate_part_name(name) when byte_size(name) == 0, do: {:error, "can't be empty string"}
  defp validate_part_name(_name), do: :ok

  @type last_name :: String.t()
  precond last_name: &validate_part_name/1

  typed_schema "people", null: true do
    field(:name, :string, default: "Joe") :: name()
    field(:last_name, :string) :: last_name() | nil
    field(:age, :integer) :: non_neg_integer() | nil
    # fields below can be nil due to the null setting given above
    field(:happy, :boolean, default: true)
    field(:phone, :string)
    timestamps(type: :naive_datetime_usec)
  end

  precond t: &validate_full_name/1

  defp validate_full_name(struct) do
    if String.length(struct.name) + String.length(struct.last_name || "") > 10 do
      {:error, "Summary length of :name and :last_name can't be greater than 10 bytes."}
    else
      :ok
    end
  end

  # See how the following functions by Domo used in `changeset/2` below:
  # validate_type() - imported from Domo.Changeset

  def changeset(changeset, attrs) do
    changeset
    |> cast(attrs, __schema__(:fields))
    |> validate_type()
  end
end
