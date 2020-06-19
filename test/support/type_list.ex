defmodule TypeList do
  @moduledoc """
  A module with specs for tests.
  Elixir can't get types from a module generated in memory.
  It can get types only from module with BEAM file generated.
  Because of that we have file here.
  """
  defmodule Person do
    @moduledoc false
    defstruct([:name])
    @type t :: %__MODULE__{name: String.t()}
  end

  defmodule StructAll do
    @moduledoc false
    defmodule Submodule do
      @moduledoc false
      @type t :: atom
    end

    defstruct([
      :atom,
      :peer,
      :string,
      :integer,
      :float,
      :bitstring,
      :fun,
      :pid,
      :port,
      :ref,
      :tuple,
      :list,
      :map
    ])

    @type t :: %__MODULE__{
            atom: TypeList.an_atom(),
            peer: TypeList.cust_person(),
            string: TypeList.opaque_str(),
            integer: TypeList.an_integer(),
            float: TypeList.a_float(),
            bitstring: TypeList.a_bitstring(),
            fun: TypeList.a_fun(),
            pid: TypeList.a_pid(),
            port: TypeList.a_port(),
            ref: TypeList.a_reference(),
            tuple: TypeList.a_tuple(),
            list: TypeList.a_list(),
            map: TypeList.a_map()
          }
  end

  alias StructAll.Submodule

  @type a_str :: String.t()
  @type an_atom :: Submodule.t()
  @type an_integer :: integer
  @type a_float :: float
  @type a_bitstring :: bitstring
  @type a_fun :: fun
  @type a_pid :: pid
  @type a_port :: port
  @type a_reference :: reference
  @type a_tuple :: tuple
  @type a_list :: list
  @type a_map :: map
  @type cust_person :: Person.t()

  @type s :: a_str()
  @typep priv_str :: s()
  @opaque opaque_str :: priv_str()

  @type map_as_bool :: as_boolean(%{a_key: opaque_str()})
  @type map_all :: %{
          optional(an_atom()) => cust_person(),
          required(opaque_str()) => an_atom(),
          required(an_integer()) => a_float(),
          required(a_bitstring()) => a_fun(),
          required(a_pid()) => a_port(),
          required(a_reference()) => a_tuple(),
          required(a_list()) => a_map()
        }

  @type struct_all :: StructAll.t()
  @type tuple_all ::
          {an_atom(),
           {cust_person(),
            {opaque_str(),
             {an_integer(),
              {a_float(),
               {a_bitstring(),
                {a_fun(),
                 {a_pid(), {a_port(), {a_reference(), {a_tuple(), {a_list(), a_map()}}}}}}}}}}}}

  @type list_cust_person :: [cust_person()]

  @type kw_list_all :: [
          atom: TypeList.an_atom(),
          peer: TypeList.cust_person(),
          string: TypeList.opaque_str(),
          integer: TypeList.an_integer(),
          float: TypeList.a_float(),
          bitstring: TypeList.a_bitstring(),
          fun: TypeList.a_fun(),
          pid: TypeList.a_pid(),
          port: TypeList.a_port(),
          ref: TypeList.a_reference(),
          tuple: TypeList.a_tuple(),
          list: TypeList.a_list(),
          map: TypeList.a_map()
        ]

  @type person_or_map ::
          {atom | integer,
           {:foo | :bar, [an_atom()],
            {:nested | an_integer() | a_float(), cust_person() | %{p_name: opaque_str()}}}}

  def env, do: __ENV__
end
