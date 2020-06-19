defmodule Domo.TypeSpecMatchable.DefinedTypes do
  @moduledoc false

  alias Domo.TypeSpecMatchable
  alias Domo.TypeSpecMatchable.BeamType
  alias Domo.TypeSpecMatchable.QuotedType
  alias Domo.TypeSpecMatchable.RemoteType

  @spec expand_usertype(QuotedType.t(), TypeSpecMatchable.metadata()) ::
          {:ok, QuotedType.t(), TypeSpecMatchable.metadata()} | {:error, any}
  def expand_usertype(_bt, nil), do: {:error, :no_metadata}

  def expand_usertype({tn, _, _} = bt, metadata) do
    case QuotedType.is_user_type(bt) do
      :ok -> expand_beam_type(tn, metadata)
      err -> err
    end
  end

  def expand_usertype(bt, _metadata), do: {:error, {:unexpandable, bt}}

  @spec expand_beam_type(atom, TypeSpecMatchable.metadata()) ::
          {:ok, QuotedType.t(), TypeSpecMatchable.metadata()} | {:error, any}
  defp expand_beam_type(bt, metadata) do
    case BeamType.expand_type(bt, Map.get(metadata, :types, [])) do
      {:ok, {:type, bt}} ->
        final_type(Code.Typespec.type_to_quoted(bt), metadata)

      {:ok, {:remote_type, rt}} ->
        expand_final_remote_type(Code.Typespec.type_to_quoted(rt), metadata)

      err ->
        err
    end
  end

  @spec final_type(QuotedType.t(), TypeSpecMatchable.metadata()) ::
          {:ok, QuotedType.t(), TypeSpecMatchable.metadata()} | {:error, any}
  def final_type(type, metadata) do
    case QuotedType.get_final_type(type) do
      {:ok, type} -> {:ok, type, metadata}
      err -> err
    end
  end

  @spec expand_final_remote_type(QuotedType.t(), TypeSpecMatchable.metadata()) ::
          {:ok, QuotedType.t(), TypeSpecMatchable.metadata()} | {:error, any}
  defp expand_final_remote_type(type, metadata) do
    case QuotedType.get_final_type(type) do
      {:ok, type} -> RemoteType.expand(type, metadata)
      err -> err
    end
  end
end
