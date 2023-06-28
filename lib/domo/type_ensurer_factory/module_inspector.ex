defmodule Domo.TypeEnsurerFactory.ModuleInspector do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.ResolvePlanner
  alias Domo.TermSerializer

  @type_ensurer_atom :TypeEnsurer

  elixir_version =
    :elixir
    |> Application.spec(:vsn)
    |> to_string()
    |> String.replace(~r/-.*$/, "")
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)

  @struct_attribute (case elixir_version do
                       [1, minor, _] when minor < 12 -> :struct
                       # In elixir v1.12.0 :struct is renamed to :__struct__ https://github.com/elixir-lang/elixir/pull/10354
                       _ -> :__struct__
                     end)

  defdelegate ensure_loaded?(module), to: Code

  def module_context?(env) do
    not is_nil(env.module) and is_nil(env.function)
  end

  def struct_attribute, do: @struct_attribute

  def struct_module?(env_module) do
    Module.has_attribute?(env_module, @struct_attribute)
  end

  def type_ensurer_atom, do: @type_ensurer_atom

  def type_ensurer(module), do: Module.concat(module, @type_ensurer_atom)

  def beam_types_hash(module) do
    case beam_types(module) do
      {:ok, type_list} -> TermSerializer.term_md5(type_list)
      _error -> nil
    end
  end

  def has_type_ensurer?(module) do
    type_ensurer = type_ensurer(module)
    Code.ensure_loaded?(type_ensurer)
  end

  def beam_types(module) do
    case fetch_direct_types(module) do
      {:ok, _type_list} = ok ->
        ok

      :error ->
        # We use the presences of the :in_memory ResolvePlanner as a
        # proxy for whether we're running outside of `mix compile` or
        # not. We can not reliably use CodeEvaluation.in_mix_compile?,
        # because it will return false if code got deleted and no
        # compilation was necessary.
        if ResolvePlanner.started?(:in_memory) do
          ResolvePlanner.get_types(:in_memory, module)
        else
          {:error, {:no_beam_file, module}}
        end
    end
  end

  def fetch_direct_types(module_or_bytecode) do
    case Code.Typespec.fetch_types(module_or_bytecode) do
      {:ok, type_list} -> {:ok, Enum.reject(type_list, &parametrized_type?/1)}
      :error -> :error
    end
  end

  defp parametrized_type?({kind, {_name, _definition, [_ | _] = _arg_list}}) when kind in [:type, :opaque] do
    true
  end

  defp parametrized_type?(_type) do
    false
  end

  def find_t_type(type_list) do
    notfound = {:error, {:type_not_found, "t"}}

    case Enum.find_value(type_list, notfound, &match_quoted_type(:t, &1)) do
      {:ok, quoted_type} ->
        {:"::", _, [{_name, _, _}, target_type]} = quoted_type
        {:ok, clean_meta(target_type), []}

      {:error, _} = err ->
        err
    end
  end

  defp match_quoted_type(name, {:"::", _, [{name, _, _}, _target]} = type) do
    {:ok, type}
  end

  defp match_quoted_type(_, _), do: nil

  def find_beam_type_quoted(name, type_list, dereferenced_types \\ []) do
    notfound = {:error, {:type_not_found, Atom.to_string(name)}}
    notsupported = {:error, {:parametrized_type_not_supported, name}}

    case Enum.find_value(type_list, notfound, &having_beam_name(name, &1)) do
      {:ok, :user_type, _target_name, {_, {:user_type, _, _, [_ | _] = _args}, _}} ->
        notsupported

      {:ok, :user_type, target_name, _type} ->
        find_beam_type_quoted(target_name, type_list, [target_name | dereferenced_types])

      {:ok, _type_kind, _target_name, type} ->
        {:"::", _, [_name, target_quoted_type]} = Code.Typespec.type_to_quoted(type)
        {:ok, clean_meta(target_quoted_type), Enum.reverse(dereferenced_types)}

      {:error, _} = err ->
        err
    end
  end

  defp having_beam_name(name, {_kind, {name, {target_kind, _, target_name, _}, _} = spec}),
    do: {:ok, target_kind, target_name, spec}

  defp having_beam_name(name, {_kind, {name, {target_kind, _, _}, _} = spec}),
    do: {:ok, target_kind, nil, spec}

  defp having_beam_name(_, _), do: nil

  defp clean_meta({lhs, _meta, rhs}) do
    {clean_meta(lhs), [], clean_meta(rhs)}
  end

  defp clean_meta({lhs, rhs}) do
    {clean_meta(lhs), clean_meta(rhs)}
  end

  defp clean_meta([_ | _] = term) do
    Enum.map(term, &clean_meta/1)
  end

  defp clean_meta(term) do
    term
  end
end
