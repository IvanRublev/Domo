# credo:disable-for-this-file
defmodule NoTypesModule do
  @moduledoc false
end

defmodule ModuleNested do
  @moduledoc false

  @type mn_float :: float()
  @type various_type :: atom() | integer() | float() | list()

  defmodule Module do
    @moduledoc false

    @type mod_float :: ModuleNested.mn_float()

    defmodule Submodule do
      @moduledoc false

      alias ModuleNested.Module

      @type t :: atom()
      @opaque op :: integer()
      @type sub_float :: Module.mod_float()
    end

    defmodule OneField do
      defstruct [:field]

      @type local_atom :: atom()
      @type t :: %__MODULE__{field: local_atom()}
    end
  end

  def env, do: __ENV__
end

defmodule RemoteUserType do
  @moduledoc false

  alias ModuleNested.Module.Submodule
  alias ModuleNested.Module.OneField

  defstruct [:field]
  @type t :: %__MODULE__{field: Submodule.t()}
  @type some_int :: Submodule.op()
  @type sub_float :: Submodule.sub_float()
  @type tof :: %__MODULE__{field: OneField.t()}
  @type local_int :: integer()
  @type tuple_vars :: {first :: float(), second :: local_int()}

  def env, do: __ENV__
end

defmodule LocalUserType do
  @moduledoc false

  @type int :: integer()
  @typep i :: int()
  @opaque indirect_int :: i()

  @type list_remote_user_type :: [RemoteUserType.sub_float()]
  @type remote_tuple_vars :: RemoteUserType.tuple_vars()
  @type some_atom :: Submodule.t()

  defstruct [
    :field,
    :remote_field,
    :remote_field_float,
    :remote_field_sub_float
  ]

  @type t :: %__MODULE__{
          field: int(),
          remote_field: list_remote_user_type(),
          remote_field_float: ModuleNested.mn_float(),
          remote_field_sub_float: RemoteUserType.sub_float()
        }

  def env, do: __ENV__
end

defmodule UserTypes do
  @type various_type :: atom() | integer() | float() | list()
  @type map_field_or_typed :: %{key1: 1 | :none}
  @type numbers :: number()
  @type strings :: String.t()
  @type two_elem_tuple :: {atom(), list()}
  @type some_numbers :: numbers()
  @type remote_mn_float :: ModuleNested.mn_float()
  @type atom_keyword :: keyword(atom())
  @type atom_as_boolean :: as_boolean(atom())
  @type a_timeout :: timeout()
  @type an_iolist :: iolist()
  @type an_iodata :: iodata()
  @type an_identifier :: identifier()
  @type a_boolean :: boolean()
  @type an_any :: any()
  @type a_term :: term()
  @type number_one :: 1
  @type atom_hello :: :hello
  @type empty_list :: []
  @type empty_bitstring :: <<>>
  @type empty_tuple :: {}
  @type empty_map :: %{}
  @type a_none :: none()
  @type a_noreturn :: no_return()
  @type a_pid :: pid()
  @type a_port :: port()
  @type a_reference :: reference()
  @type remote_type :: RemoteUserType.t()

  def env, do: __ENV__

  # Following functions are to test precondition calls
  def __precond__(:t, value), do: apply(&(&1.first > 2), [value])
  def __precond__(:positive_integer, value), do: apply(&(&1 > 0), [value])
  def __precond__(:positive_float, value), do: apply(&(&1 > 1.1), [value])
  def __precond__(:first_elem_gt_5, value), do: apply(&(elem(&1, 0) > 5), [value])
  def __precond__(:binary_6, value), do: apply(&(String.length(&1) == 6), [value])
  def __precond__(:hd_gt_7, value), do: apply(&(hd(&1) > 7), [value])
  def __precond__(:kw_length_2, value), do: apply(&(Enum.count(&1) == 2), [value])
  def __precond__(:map_value_sum_2_4, value), do: apply(&(&1 |> Map.values() |> Enum.sum() >= 2.4), [value])

  def __precond__(:capital_title, value) do
    apply(
      fn struct ->
        s = String.at(struct.title, 0)
        String.upcase(s) == s
      end,
      [value]
    )
  end

  def __precond__(:map_set_only_floats, value), do: apply(&Enum.all?(&1, fn num -> is_float(num) end), [value])

  def __precond__(:inner_range_5_8, value) do
    apply(
      fn first..last ->
        [first, last] = Enum.sort([first, last])
        first > 5 and last < 8
      end,
      [value]
    )
  end

  def __precond__(:t_custom_msg, value) do
    if apply(&(&1.first > 2), [value]) do
      :ok
    else
      {:error, "First field value should be greater then two"}
    end
  end

  def __precond__(:positive_integer_custom_msg, value) do
    if apply(&(&1 > 0), [value]) do
      :ok
    else
      {:error, "Expected positive integer"}
    end
  end
end
