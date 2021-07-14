defmodule ExamplePreciousDb.Accounts.User do
  use Ecto.Schema
  use Domo
  import Ecto.Changeset
  import Domo.Changeset

  schema "users" do
    field :age, :integer
    field :first_name, :string
    field :last_name, :string

    timestamps()
  end

  @type t :: %__MODULE__{
    age: pos_integer() | nil,
    first_name: short_name() | nil,
    last_name: long_name() | nil
  }

  @type short_name :: String.t()
  precond short_name: &if(String.length(&1) > 10, do: {:error, "expected 10 characters max"}, else: :ok)

  @type long_name :: String.t()
  precond long_name: &if(String.length(&1) > 20, do: {:error, "expected 20 characters max"}, else: :ok)

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:first_name, :last_name, :age])
    |> validate_type()
  end
end
