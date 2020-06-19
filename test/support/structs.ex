defmodule TypedStructSamplePlugin do
  @moduledoc false
  use TypedStruct.Plugin

  @impl true
  @spec init(keyword()) :: Macro.t()
  defmacro init(_opts) do
    quote do
      def plugin_injected?, do: true
    end
  end
end

defmodule NoDefaultOneFieldStruct do
  @moduledoc false
  use Domo

  typedstruct do
    plugin(TypedStructSamplePlugin)

    field :first, integer
    field :second, float, default: 1.0
  end
end

defmodule AllDefaultsStruct do
  @moduledoc false
  use Domo

  typedstruct do
    plugin(TypedStructSamplePlugin)

    field :first, integer, default: 1
    field :second, float, default: 1.0
  end
end

defmodule TwoFieldStruct do
  @moduledoc false
  use Domo

  typedstruct do
    plugin(TypedStructSamplePlugin)

    field :first, integer
    field :second, float
  end
end

defmodule OverridenNew do
  @moduledoc false
  use Domo

  typedstruct do
    field :first, integer
    field :second, integer, default: 0
  end

  def new!(enumerable), do: super(Enum.into(%{second: 4}, enumerable))
  def new(enumerable), do: super(Enum.into(%{second: 4}, enumerable))

  def merge!(struct, enumerable), do: super(struct, Enum.into(%{first: 555}, enumerable))
  def merge(struct, enumerable), do: super(struct, Enum.into(%{first: 666}, enumerable))

  def put!(struct, key, value), do: super(struct, key, 20 + value)
  def put(struct, key, value), do: super(struct, key, 60 + value)
end

defmodule Generator do
  @moduledoc false
  @type an_atom :: atom
  @type a_str :: String.t()

  def one, do: 1
end

defmodule IncorrectDefault do
  @moduledoc false
  use Domo

  typedstruct do
    field :default, Generator.an_atom(), default: Generator.one()
    field :second, Generator.a_str()
    field :third, float
  end
end

defmodule NoFieldsStruct do
  @moduledoc false
  use Domo

  # coveralls-ignore-start
  typedstruct do
  end

  # coveralls-ignore-stop
end
