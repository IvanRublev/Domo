defmodule Domo.Changeset do
  @moduledoc """
  Module with validation functions for [Echo.Changeset](https://hexdocs.pm/ecto/Ecto.Changeset.html#module-validations-and-constraints).

  To make `validate_type/*` functions work `t()` type can be defined for the schema like the following:

      defmodule User do
        use Ecto.Schema
        use Domo
        import Ecto.Changeset
        import Domo.Changeset

        schema "users" do
          field :name
          field :email
          field :age, :integer
        end

        @type t :: %__MODULE__{
          name :: String.t() | nil,
          email :: String.t() | nil,
          age :: integer() | nil
        }

        def changeset(user, params \\ %{}) do
          user
          |> cast(params, [:name, :email, :age])
          |> validate_required([:name, :email])
          |> validate_type()
        end
      end
  """

  alias Domo.ErrorBuilder
  alias Domo.Raises

  @doc """
  Validates field change values conforms to appropriate types defined within the schema's t() type.

  It perform the validation only if a change value is not nil.

  In case there's at least one error, the list of errors will be appended to the `:errors` field of the changeset and the `:valid?` flag will be set to false.
  """
  def validate_type(%{data: %schema{}} = changeset) do
    validate_type(changeset, schema)
  end

  def validate_type(_changeset) do
    Raises.raise_no_schema_module()
  end

  @doc """
  Similar to validate_type/1, but can work with a map changeset. Takes struct module name as `struct`.

  ## Examples

      {%{}, %{name: :string, email: :string, age: :integer}}
      |> cast(%{name: "Hello world", email: "some@address", age: 21}, [:name, :email, :age])
      |> validate_type(User)
  """
  def validate_type(changeset, struct) when is_atom(struct) do
    type_ensurer = Module.concat(struct, TypeEnsurer)

    if Code.ensure_loaded?(type_ensurer) do
      fields =
        type_ensurer
        |> apply(:fields, [])
        |> Enum.reject(&(&1 |> Atom.to_string() |> String.starts_with?("__")))

      Enum.reduce(fields, changeset, &do_validate_change(type_ensurer, &2, &1))
    else
      Raises.raise_no_type_ensurer_for_schema_module(struct)
    end
  end

  @doc """
  Similar to validate_type/1, but validates only given `fields`.
  """
  def validate_type_fields(changeset, fields)

  def validate_type_fields(changeset, []) do
    changeset
  end

  def validate_type_fields(%{data: %schema{}} = changeset, [_ | _] = fields) do
    validate_type_fields(changeset, schema, fields)
  end

  def validate_type_fields(_changeset, [_ | _] = _fields) do
    Raises.raise_no_schema_module()
  end

  @doc """
  Similar to validate_type/2, but validates only given `fields`.
  """
  def validate_type_fields(changeset, struct, fields)

  def validate_type_fields(changeset, _struct, []) do
    changeset
  end

  def validate_type_fields(changeset, struct, fields) do
    type_ensurer = Module.concat(struct, TypeEnsurer)

    if Code.ensure_loaded?(type_ensurer) do
      Enum.reduce(fields, changeset, &do_validate_change(type_ensurer, &2, &1))
    else
      Raises.raise_no_type_ensurer_for_schema_module(struct)
    end
  end

  defp do_validate_change(type_ensurer, changeset, field) do
    apply(Ecto.Changeset, :validate_change, [
      changeset,
      field,
      fn field, value ->
        case apply(type_ensurer, :ensure_field_type, [{field, value}]) do
          :ok ->
            []

          {:error, _message} = error ->
            [{field, ErrorBuilder.pretty_error(error)}]
        end
      end
    ])
  end
end
