defprotocol Domo.TypeSpecMatchable do
  @moduledoc """
  A protocol to match a value against a typespec.
  """

  alias Domo.TypeSpecMatchable
  alias TypeSpecMatchable.BeamType

  @fallback_to_any true
  @type t :: TypeSpecMatchable.t()
  @type t_spec :: Macro.t()
  @type metadata :: %{
          required(:env) => Macro.Env.t(),
          optional(:stacktrace) => [any],
          optional(:types) => BeamType.module_types()
        }

  @doc """
  Returns true if the given term matches a single typespec
  given in the quoted form.

  The metadata is a map with info to resolve remote types. Should contain
  the caller environment with the `env` key. Other keys can be
  populated during the run internally.
  """
  @spec match_spec?(t(), t_spec(), metadata()) :: boolean()
  def match_spec?(term, spec, metadata)
end

defimpl Domo.TypeSpecMatchable, for: Atom do
  alias Domo.TypeSpecMatchable

  def match_spec?(_term, {shortcut, _, _}, _metadata)
      when shortcut in [:any, :term, :atom, :module, :node],
      do: true

  def match_spec?(term, {{:., _, [_, _]}, _, _} = rtp, metadata) do
    case TypeSpecMatchable.RemoteType.expand(rtp, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
    end
  end

  def match_spec?(term, {:|, _, _} = type, metadata) do
    Enum.empty?(TypeSpecMatchable.TermList.reject([term], type, metadata))
  end

  def match_spec?(term, {:as_boolean, _, [arg]}, metadata),
    do: match_spec?(term, arg, metadata)

  def match_spec?(term, {:boolean, _, _}, _metadata)
      when is_boolean(term),
      do: true

  def match_spec?(:infinity, {:timeout, _, _}, _metadata), do: true

  def match_spec?(term, expected, _metadata) when is_atom(expected) do
    if module_atom?(term) and false == Code.ensure_loaded?(term) do
      IO.warn("No loaded module for value #{inspect(term)}. Missing alias?")
    end

    term == expected
  end

  def match_spec?(term, spec, metadata) do
    if match?({:__aliases__, _, _}, spec) do
      module_type = Macro.expand(spec, metadata.env)
      if false == Code.ensure_loaded?(module_type) do
        IO.warn("No loaded module for type #{inspect(module_type)}. Missing alias?")
      end
    end

    case TypeSpecMatchable.DefinedTypes.expand_usertype(spec, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
      _ -> false
    end
  end

  defp module_atom?(term) do
    first_letter = hd(Atom.to_charlist(term))
    65 <= first_letter and first_letter <= 90
  end
end

defimpl Domo.TypeSpecMatchable, for: Integer do
  alias Domo.TypeSpecMatchable

  def match_spec?(_term, {shortcut, _, _}, _metadata)
      when shortcut in [:any, :term, :integer, :number],
      do: true

  def match_spec?(term, {{:., _, [_, _]}, _, _} = rtp, metadata) do
    case TypeSpecMatchable.RemoteType.expand(rtp, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
    end
  end

  def match_spec?(term, {:|, _, _} = type, metadata) do
    Enum.empty?(TypeSpecMatchable.TermList.reject([term], type, metadata))
  end

  def match_spec?(term, {:as_boolean, _, [arg]}, metadata),
    do: match_spec?(term, arg, metadata)

  def match_spec?(term, expected, _metadata)
      when is_integer(expected) and term == expected,
      do: true

  def match_spec?(term, {:.., _, [from, to]}, _metadata)
      when is_integer(from) and is_integer(to) and term >= from and term <= to,
      do: true

  def match_spec?(term, {:neg_integer, _, _}, _metadata) when term < 0, do: true
  def match_spec?(term, {:pos_integer, _, _}, _metadata) when term > 0, do: true
  def match_spec?(term, {:non_neg_integer, _, _}, _metadata) when term >= 0, do: true
  def match_spec?(term, {:timeout, _, _}, _metadata) when term >= 0, do: true

  def match_spec?(term, {shortcut, _, _}, _metadata)
      when shortcut in [:arity, :byte] and term >= 0 and term <= 255,
      do: true

  def match_spec?(term, {:char, _, _}, _metadata)
      when term >= 0 and term <= 0x10FFFF,
      do: true

  def match_spec?(term, spec, metadata) do
    case TypeSpecMatchable.DefinedTypes.expand_usertype(spec, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
      _ -> false
    end
  end
end

defimpl Domo.TypeSpecMatchable, for: Float do
  alias Domo.TypeSpecMatchable

  def match_spec?(_term, {shortcut, _, _}, _metadata)
      when shortcut in [:any, :term, :float, :number],
      do: true

  def match_spec?(term, {{:., _, [_, _]}, _, _} = rtp, metadata) do
    case TypeSpecMatchable.RemoteType.expand(rtp, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
    end
  end

  def match_spec?(term, {:|, _, _} = type, metadata) do
    Enum.empty?(TypeSpecMatchable.TermList.reject([term], type, metadata))
  end

  def match_spec?(term, {:as_boolean, _, [arg]}, metadata),
    do: match_spec?(term, arg, metadata)

  def match_spec?(term, spec, metadata) do
    case TypeSpecMatchable.DefinedTypes.expand_usertype(spec, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
      _ -> false
    end
  end
end

defimpl Domo.TypeSpecMatchable, for: BitString do
  alias Domo.TypeSpecMatchable

  def match_spec?(_term, {shortcut, _, _}, _metadata) when shortcut in [:any, :term], do: true

  def match_spec?(term, {{:., _, [_, _]}, _, _} = rtp, metadata) do
    case TypeSpecMatchable.RemoteType.expand(rtp, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
    end
  end

  def match_spec?(term, {:|, _, _} = type, metadata) do
    Enum.empty?(TypeSpecMatchable.TermList.reject([term], type, metadata))
  end

  def match_spec?(term, {:as_boolean, _, [arg]}, metadata),
    do: match_spec?(term, arg, metadata)

  def match_spec?(<<>>, {:<<>>, _, _}, _metadata), do: true

  def match_spec?(term, {:bitstring, _, _}, _metadata)
      when bit_size(term) > 0,
      do: true

  def match_spec?(term, {shortcut, _, _}, _metadata)
      when shortcut in [:binary, :iodata] and rem(bit_size(term), 8) == 0,
      do: true

  def match_spec?(term, {:<<>>, _, [{:"::", _, [{:_, _, _}, bit_count]}]}, _metadata)
      when bit_size(term) == bit_count,
      do: true

  def match_spec?(
        term,
        {:<<>>, _, [{:"::", _, [{:_, _, _}, {:*, _, [{:_, _, _}, chunk_bit_count]}]}]},
        _metadata
      )
      when rem(bit_size(term), chunk_bit_count) == 0,
      do: true

  def match_spec?(
        term,
        {:<<>>, _,
         [
           {:"::", _, [{:_, _, _}, prefix_bit_count]},
           {:"::", _, [{:_, _, _}, {:*, _, [{:_, _, _}, chunk_bit_count]}]}
         ]},
        _metadata
      )
      when rem(bit_size(term) - prefix_bit_count, chunk_bit_count) == 0,
      do: true

  def match_spec?(term, spec, metadata) do
    case TypeSpecMatchable.DefinedTypes.expand_usertype(spec, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
      _ -> false
    end
  end
end

defimpl Domo.TypeSpecMatchable, for: Function do
  alias Domo.TypeSpecMatchable

  @doc "Checks the arity only with the given typespec"
  def match_spec?(_term, {shortcut, _, _}, _metadata)
      when shortcut in [:any, :term, :fun, :function],
      do: true

  def match_spec?(term, {{:., _, [_, _]}, _, _} = rtp, metadata) do
    case TypeSpecMatchable.RemoteType.expand(rtp, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
    end
  end

  def match_spec?(term, {:|, _, _} = type, metadata) do
    Enum.empty?(TypeSpecMatchable.TermList.reject([term], type, metadata))
  end

  def match_spec?(term, {:as_boolean, _, [arg]}, metadata),
    do: match_spec?(term, arg, metadata)

  def match_spec?(term, [{:->, _, [args, _]}], metadata),
    do: match_spec?(term, args, metadata)

  def match_spec?(term, [], _metadata),
    do: Function.info(term, :arity) == {:arity, 0}

  def match_spec?(_term, [{:..., _, _}], _metadata), do: true

  def match_spec?(term, arg_list, _metadata) when is_list(arg_list),
    do: Function.info(term, :arity) == {:arity, length(arg_list)}

  def match_spec?(term, spec, metadata) do
    case TypeSpecMatchable.DefinedTypes.expand_usertype(spec, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
      _ -> false
    end
  end
end

defimpl Domo.TypeSpecMatchable, for: PID do
  alias Domo.TypeSpecMatchable

  def match_spec?(_term, {shortcut, _, _}, _metadata)
      when shortcut in [:any, :term, :pid, :identifier],
      do: true

  def match_spec?(term, {{:., _, [_, _]}, _, _} = rtp, metadata) do
    case TypeSpecMatchable.RemoteType.expand(rtp, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
    end
  end

  def match_spec?(term, {:|, _, _} = type, metadata) do
    Enum.empty?(TypeSpecMatchable.TermList.reject([term], type, metadata))
  end

  def match_spec?(term, {:as_boolean, _, [arg]}, metadata),
    do: match_spec?(term, arg, metadata)

  def match_spec?(term, spec, metadata) do
    case TypeSpecMatchable.DefinedTypes.expand_usertype(spec, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
      _ -> false
    end
  end
end

defimpl Domo.TypeSpecMatchable, for: Port do
  alias Domo.TypeSpecMatchable

  def match_spec?(_term, {shortcut, _, _}, _metadata)
      when shortcut in [:any, :term, :port, :identifier],
      do: true

  def match_spec?(term, {{:., _, [_, _]}, _, _} = rtp, metadata) do
    case TypeSpecMatchable.RemoteType.expand(rtp, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
    end
  end

  def match_spec?(term, {:|, _, _} = type, metadata) do
    Enum.empty?(TypeSpecMatchable.TermList.reject([term], type, metadata))
  end

  def match_spec?(term, {:as_boolean, _, [arg]}, metadata),
    do: match_spec?(term, arg, metadata)

  def match_spec?(term, spec, metadata) do
    case TypeSpecMatchable.DefinedTypes.expand_usertype(spec, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
      _ -> false
    end
  end
end

defimpl Domo.TypeSpecMatchable, for: Reference do
  alias Domo.TypeSpecMatchable

  def match_spec?(_term, {shortcut, _, _}, _metadata)
      when shortcut in [:any, :term, :reference, :identifier],
      do: true

  def match_spec?(term, {{:., _, [_, _]}, _, _} = rtp, metadata) do
    case TypeSpecMatchable.RemoteType.expand(rtp, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
    end
  end

  def match_spec?(term, {:|, _, _} = type, metadata) do
    Enum.empty?(TypeSpecMatchable.TermList.reject([term], type, metadata))
  end

  def match_spec?(term, {:as_boolean, _, [arg]}, metadata),
    do: match_spec?(term, arg, metadata)

  def match_spec?(term, spec, metadata) do
    case TypeSpecMatchable.DefinedTypes.expand_usertype(spec, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
      _ -> false
    end
  end
end

defimpl Domo.TypeSpecMatchable, for: Tuple do
  alias Domo.TypeSpecMatchable

  def match_spec?(_term, {shortcut, _, _}, _metadata) when shortcut in [:any, :term], do: true

  def match_spec?(term, {{:., _, [_, _]}, _, _} = rtp, metadata) do
    case TypeSpecMatchable.RemoteType.expand(rtp, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
    end
  end

  def match_spec?(term, {:|, _, _} = type, metadata) do
    Enum.empty?(TypeSpecMatchable.TermList.reject([term], type, metadata))
  end

  def match_spec?(term, {:as_boolean, _, [arg]}, metadata),
    do: match_spec?(term, arg, metadata)

  def match_spec?(_term, {:tuple, _, _}, _metadata), do: true

  def match_spec?({m, f, a}, {:mfa, _, _}, metadata) do
    TypeSpecMatchable.match_spec?(m, {:module, [], []}, metadata) and
      TypeSpecMatchable.match_spec?(f, {:atom, [], []}, metadata) and
      TypeSpecMatchable.match_spec?(a, {:arity, [], []}, metadata)
  end

  def match_spec?(term, {:{}, _, []}, _metadata) when tuple_size(term) == 0,
    do: true

  def match_spec?(term, {:{}, _, [arg]}, metadata) when tuple_size(term) == 1 do
    Enum.empty?(TypeSpecMatchable.TermList.reject(Tuple.to_list(term), arg, metadata))
  end

  def match_spec?(term, {arg1, arg2}, metadata) when tuple_size(term) == 2 do
    TypeSpecMatchable.match_spec?(elem(term, 0), arg1, metadata) and
      TypeSpecMatchable.match_spec?(elem(term, 1), arg2, metadata)
  end

  def match_spec?(term, {:{}, _, args}, metadata)
      when is_list(args) and tuple_size(term) == length(args) do
    term
    |> Tuple.to_list()
    |> Enum.zip(args)
    |> Enum.all?(fn {term, spec} ->
      TypeSpecMatchable.match_spec?(term, spec, metadata)
    end)
  end

  def match_spec?(term, spec, metadata) do
    case TypeSpecMatchable.DefinedTypes.expand_usertype(spec, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
      _ -> false
    end
  end
end

defimpl Domo.TypeSpecMatchable, for: List do
  alias Domo.TypeSpecMatchable

  defmodule ImproperList do
    @moduledoc false

    def match_spec?([head | tail], head_type, termination_type, metadata) do
      TypeSpecMatchable.match_spec?(head, head_type, metadata) and
        match_spec?(tail, head_type, termination_type, metadata)
    end

    def match_spec?(termination, _, termination_type, metadata) do
      TypeSpecMatchable.match_spec?(termination, termination_type, metadata)
    end
  end

  defp type_arg(arg) when is_atom(arg), do: {arg, [], []}

  defp type(name, arg) when is_atom(name),
    do: {name, [], [type_arg(arg)]}

  defp type(name, arg1, arg2) when is_atom(name),
    do: {name, [], [type_arg(arg1), type_arg(arg2)]}

  # --------------
  def match_spec?(_term, {shortcut, _, _}, _metadata) when shortcut in [:any, :term], do: true

  def match_spec?(term, {{:., _, [_, _]}, _, _} = rtp, metadata) do
    case TypeSpecMatchable.RemoteType.expand(rtp, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
    end
  end

  def match_spec?(term, {:|, _, _} = type, metadata) do
    Enum.empty?(TypeSpecMatchable.TermList.reject([term], type, metadata))
  end

  def match_spec?(term, {:iodata, _, _}, metadata),
    do: match_spec?(term, type_arg(:iolist), metadata)

  def match_spec?(term, {:iolist, _, _}, metadata) do
    match_spec?(term, type(:maybe_improper_list, :byte, :binary), metadata) or
      match_spec?(term, type(:maybe_improper_list, :binary, :binary), metadata) or
      match_spec?(term, type(:maybe_improper_list, :iolist, :binary), metadata)
  end

  def match_spec?(term, {:maybe_improper_list, _, [{_, _, _} = head_type, {_, _, _}]}, metadata)
      when length(term) >= 0 do
    # proper
    match_spec?(term, [head_type], metadata)
  end

  def match_spec?(
        term,
        {:maybe_improper_list, _, [{_, _, _} = head_type, {_, _, _} = termination_type]},
        metadata
      ) do
    ImproperList.match_spec?(term, head_type, termination_type, metadata)
  end

  def match_spec?(term, {:maybe_improper_list, _, _}, metadata) do
    match_spec?(term, type(:maybe_improper_list, :any, :any), metadata)
  end

  def match_spec?(
        term,
        {:nonempty_maybe_improper_list, _, [{_, _, _} = head_type, {_, _, _}]},
        metadata
      )
      when length(term) > 0 do
    # proper
    match_spec?(term, [head_type], metadata)
  end

  def match_spec?(
        [_ | _] = term,
        {:nonempty_maybe_improper_list, _, [{_, _, _} = head_type, {_, _, _} = termination_type]},
        metadata
      ) do
    ImproperList.match_spec?(term, head_type, termination_type, metadata)
  end

  def match_spec?([_ | _] = term, {:nonempty_maybe_improper_list, _, _}, metadata) do
    match_spec?(term, type(:nonempty_maybe_improper_list, :any, :any), metadata)
  end

  def match_spec?(
        [_ | _] = term,
        {:nonempty_improper_list, _, [{_, _, _} = head_type, {_, _, _} = termination_type]},
        metadata
      ) do
    ImproperList.match_spec?(term, head_type, termination_type, metadata)
  end

  def match_spec?(term, {:charlist, _, _}, metadata),
    do: match_spec?(term, [type_arg(:char)], metadata)

  def match_spec?(term, {:nonempty_charlist, _, _}, metadata),
    do: match_spec?(term, [type_arg(:char), type_arg(:...)], metadata)

  def match_spec?(term, {:nonempty_list, _, [{_, _, _}] = type}, metadata),
    do: match_spec?(term, type ++ [type_arg(:...)], metadata)

  def match_spec?(term, {:nonempty_list, _, _}, metadata),
    do: match_spec?(term, type(:nonempty_list, :any), metadata)

  def match_spec?(term, {:list, _, [{_, _, _}] = type}, metadata),
    do: match_spec?(term, type, metadata)

  def match_spec?(term, {:list, _, _}, _metadata) when length(term) >= 0, do: true

  def match_spec?([], [], _metadata), do: true

  def match_spec?(term, [{:..., _, _}], _metadata) when length(term) > 0, do: true

  def match_spec?(_term, [{:..., _, _}], _metadata), do: false

  def match_spec?(term, [{_, _, _} = type, {:..., _, _}], metadata) when length(term) > 0,
    do: match_spec?(term, [type], metadata)

  def match_spec?([], [_type], _metadata), do: true

  def match_spec?(_term, [{:any, _, _}], _metadata), do: true

  def match_spec?(term, [{key, _} | _] = kw_types, metadata) when is_atom(key) and key != :| do
    Enum.empty?(Enum.reduce(kw_types, term, &TypeSpecMatchable.TermList.reject(&2, &1, metadata)))
  end

  def match_spec?(term, {:keyword, _, [types]}, metadata),
    do: match_spec?(term, [{type_arg(:atom), types}], metadata)

  def match_spec?(term, {:keyword, _, _}, metadata),
    do: match_spec?(term, [{type_arg(:atom), type_arg(:any)}], metadata)

  def match_spec?(term, [{key, _} | _] = kw_types, metadata) when is_atom(key) and key != :| do
    Enum.empty?(Enum.reduce(kw_types, term, &TypeSpecMatchable.TermList.reject(&2, &1, metadata)))
  end

  def match_spec?(term, [type], metadata) do
    Enum.empty?(TypeSpecMatchable.TermList.reject(term, type, metadata))
  end

  def match_spec?(term, spec, metadata) do
    case TypeSpecMatchable.DefinedTypes.expand_usertype(spec, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
      _ -> false
    end
  end
end

defimpl Domo.TypeSpecMatchable, for: Map do
  alias Domo.TypeSpecMatchable
  alias Domo.TypeSpecMatchable.TermList

  defmodule MapMatcher do
    @moduledoc false

    def match_mixed_spec?(term, req_kw_types, opt_kw_types, false = _opt_any, metadata) do
      term = Enum.reduce(opt_kw_types, term, &TermList.reject(&2, &1, metadata))

      length(term) > 0 and
        Enum.empty?(Enum.reduce(req_kw_types, term, &TermList.reject(&2, &1, metadata)))
    end

    def match_mixed_spec?(term, req_kw_types, _opt_kw_types, true = _opt_any, metadata) do
      Enum.all?(req_kw_types, fn type ->
        Enum.any?(term, &TypeSpecMatchable.match_spec?(&1, type, metadata))
      end)
    end

    def match_optional_spec?(term, kw_types, metadata) do
      Enum.empty?(Enum.reduce(kw_types, term, &TermList.reject(&2, &1, metadata)))
    end

    def match_req_spec?(term, kw_types, metadata) do
      map_size(term) > 0 and
        Enum.empty?(Enum.reduce(kw_types, term, &TermList.reject(&2, &1, metadata)))
    end
  end

  def match_spec?(_term, {shortcut, _, _}, _metadata) when shortcut in [:map, :any, :term],
    do: true

  def match_spec?(term, {{:., _, [_, _]}, _, _} = rtp, metadata) do
    case TypeSpecMatchable.RemoteType.expand(rtp, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
    end
  end

  def match_spec?(term, {:|, _, _} = type, metadata) do
    Enum.empty?(TermList.reject([term], type, metadata))
  end

  def match_spec?(term, {:%{}, _, []}, _metadata) when map_size(term) == 0,
    do: true

  def match_spec?(
        term,
        {:%{}, _, [{{_, _, [{_, _, _}]}, {_, _, _}} | _] = key_desc},
        metadata
      ) do
    {req_kw_types, opt_kw_types} =
      Enum.reduce(Enum.reverse(key_desc), {%{}, %{}}, fn {{kind, _, [key_type]}, val_type},
                                                         {req, opt} ->
        case kind do
          :required -> {Map.put(req, key_type, val_type), opt}
          :optional -> {req, Map.put(opt, key_type, val_type)}
        end
      end)

    opt_any = Enum.any?(opt_kw_types, &match?({{:any, _, _}, {:any, _, _}}, &1))
    empty_opt_kw = Enum.empty?(opt_kw_types)
    empty_req_kw = Enum.empty?(req_kw_types)

    (not empty_opt_kw and not empty_req_kw and
       MapMatcher.match_mixed_spec?(term, req_kw_types, opt_kw_types, opt_any, metadata)) or
      ((empty_opt_kw or MapMatcher.match_optional_spec?(term, opt_kw_types, metadata)) and
         (empty_req_kw or MapMatcher.match_req_spec?(term, req_kw_types, metadata)))
  end

  def match_spec?(term, {:%{}, _, [{_, _} | _] = kw_types}, metadata) do
    MapMatcher.match_req_spec?(term, kw_types, metadata)
  end

  def match_spec?(term, spec, metadata) do
    case TypeSpecMatchable.DefinedTypes.expand_usertype(spec, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
      _ -> false
    end
  end
end

defimpl Domo.TypeSpecMatchable, for: Any do
  alias Domo.TypeSpecMatchable

  def match_spec?(%_name{}, {shortcut, _, _}, _metadata)
      when shortcut in [:struct, :any, :term, :map],
      do: true

  def match_spec?(%_name{} = term, {{:., _, [_, _]}, _, _} = rtp, metadata) do
    case TypeSpecMatchable.RemoteType.expand(rtp, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
    end
  end

  def match_spec?(%_name{} = term, {:|, _, _} = type, metadata) do
    Enum.empty?(TypeSpecMatchable.TermList.reject([term], type, metadata))
  end

  def match_spec?(
        %name{} = term,
        {:%, _, [exp_alias, {:%{}, _, struct_args} = struct_type]},
        metadata
      ) do
    name == Macro.expand(exp_alias, metadata.env) and
      (struct_args == [] or
         TypeSpecMatchable.match_spec?(Map.from_struct(term), struct_type, metadata))
  end

  def match_spec?(%_name{} = term, spec, metadata) do
    case TypeSpecMatchable.DefinedTypes.expand_usertype(spec, metadata) do
      {:ok, type, metadata} -> match_spec?(term, type, metadata)
      _ -> false
    end
  end

  def match_spec?(term, spec, metadata),
    do:
      raise(
        "not implemented for #{inspect(term)} that should match type #{inspect(spec)}. Type metadata #{
          inspect(metadata)
        }"
      )
end

defmodule Domo.TypeContract do
  @moduledoc """
  A module to validate a type contract
  """

  defdelegate match_spec?(term, spec, metadata), to: Domo.TypeSpecMatchable

  @doc """
  Validates if the value matches the @type contract.

  * contract is a type spec in Elixir quoted form.
  * environment is a module's environment to resolve aliases for remote types.
    Usually, it should be a caller environment that
    the `Kernel.SpecialForms.__ENV__/0` macro returns.
  """
  @spec valid?(any, Macro.t(), Macro.Env.t()) :: boolean
  def valid?(value, contract, env) do
    match_spec?(value, contract, %{env: env})
  end
end
