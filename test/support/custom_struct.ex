# credo:disable-for-this-file
defmodule CustomStruct do
  defstruct([:title])
  @type t :: %__MODULE__{title: String.t()}

  def env, do: __ENV__
end

defmodule CustomStructWithAnyField do
  defstruct([:title, :field])
  @type t :: %__MODULE__{title: String.t(), field: any()}

  def env, do: __ENV__
end

defmodule CustomStructWithEnsureOk do
  defstruct([:title])
  @type t :: %__MODULE__{title: String.t()}

  def env, do: __ENV__

  def ensure_type_ok(value) do
    {:ok, value}
  end
end

defmodule CustomStructWithPrecond do
  import Domo

  defstruct([:title])
  @type t :: %__MODULE__{title: title}

  @type title :: String.t()
  precond title: fn _arg -> true end

  def env, do: __ENV__
end
