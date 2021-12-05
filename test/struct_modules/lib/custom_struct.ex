# credo:disable-for-this-file
defmodule CustomStruct do
  defstruct([:title])
  @type t :: %__MODULE__{title: String.t()}

  def env, do: __ENV__
end

defmodule CustomStructWithEnsureOk do
  defmodule TypeEnsurer do
    def fields(_kind), do: [:title]
    def ensure_field_type(_value), do: :ok
    def t_precondition(_value), do: :ok
  end

  defstruct([:title])
  @type t :: %__MODULE__{title: String.t()}
end

defmodule CustomStructWithPrecond do
  import Domo

  defstruct([:title])
  @type t :: %__MODULE__{title: title}

  @type title :: String.t()
  precond title: fn _arg -> true end

  def env, do: __ENV__
end
