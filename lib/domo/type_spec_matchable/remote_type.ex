defmodule Domo.TypeSpecMatchable.RemoteType do
  @moduledoc false

  alias Domo.TypeSpecMatchable
  alias Domo.TypeSpecMatchable.BeamType
  alias Domo.TypeSpecMatchable.QuotedType

  @spec expand({{:., any, list}, any, any}, TypeSpecMatchable.metadata()) ::
          {:ok, tuple, TypeSpecMatchable.metadata()} | {:error, any}
  def expand({{:., _, [rem_module, rem_type]}, _, _} = rts, metadata) do
    case type_module(Macro.expand(rem_module, metadata.env), rem_type, metadata) do
      {:ok, {:type, type}, metadata} ->
        {:ok, type, metadata}

      {:ok, {:remote_type, type}, metadata} ->
        expand(type, metadata)

      {:error, :nofile} = ret_err ->
        IO.warn("Can't expand remote type #{inspect(rts)}. Maybe missing alias to the module \
#{inspect(rem_module)} in the module #{metadata.env.module}?")
        ret_err

      {:error, err} = ret_err ->
        IO.warn("Can't expand remote type #{inspect(rts)} due to #{inspect(err)}")
        ret_err
    end
  end

  @spec type_module(atom, atom, TypeSpecMatchable.metadata()) ::
          {:ok, {:type | :remote_type, tuple}, TypeSpecMatchable.metadata()} | {:error, any}
  defp type_module(rem_module, rem_type, metadata) do
    with {:module, rem_module} <- Code.ensure_loaded(rem_module),
         {:ok, type_list} <- Code.Typespec.fetch_types(rem_module),
         {:ok, {kind, beam_t}} <- BeamType.expand_type(rem_type, type_list),
         {:ok, qt} <- QuotedType.get_final_type(Code.Typespec.type_to_quoted(beam_t)) do
      {:ok, {kind, qt}, Map.put(metadata, :types, type_list)}
    else
      :error -> {:error, :no_file}
      err -> err
    end
  end
end
