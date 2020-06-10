defmodule Domo.TypeError do
  defexception [:message]

  @impl true
  def exception(msg), do: %__MODULE__{message: msg}
end
