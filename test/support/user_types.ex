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

  def env, do: __ENV__
end

defmodule LocalUserType do
  @moduledoc false

  @type int :: integer()
  @typep i :: int()
  @opaque indirect_int :: i()

  @type list_remote_user_type :: [RemoteUserType.t()]
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
