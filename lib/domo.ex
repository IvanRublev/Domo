defmodule Domo do
  @moduledoc Domo.Doc.readme_doc("[//]: # (Documentation)")

  @new_doc Domo.Doc.readme_doc("[//]: # (new/1)")
  @new_ok_doc Domo.Doc.readme_doc("[//]: # (new_ok/2)")
  @ensure_type_doc Domo.Doc.readme_doc("[//]: # (ensure_type!/1)")
  @ensure_type_ok_doc Domo.Doc.readme_doc("[//]: # (ensure_type_ok/2)")
  @typed_fields_doc Domo.Doc.readme_doc("[//]: # (typed_fields/1)")
  @required_fields_doc Domo.Doc.readme_doc("[//]: # (required_fields/1)")

  @callback new() :: struct()
  @doc @new_doc
  @callback new(enumerable :: Enumerable.t()) :: struct()
  @callback new_ok() :: {:ok, struct()} | {:error, any()}
  @callback new_ok(enumerable :: Enumerable.t()) :: {:ok, struct()} | {:error, any()}
  @doc @new_ok_doc
  @callback new_ok(enumerable :: Enumerable.t(), opts :: keyword()) :: {:ok, struct()} | {:error, any()}
  @doc @ensure_type_doc
  @callback ensure_type!(struct :: struct()) :: struct()
  @callback ensure_type_ok(struct :: struct()) :: {:ok, struct()} | {:error, any()}
  @doc @ensure_type_ok_doc
  @callback ensure_type_ok(struct :: struct(), opts :: keyword()) :: {:ok, struct()} | {:error, any()}
  @callback typed_fields() :: [atom()]
  @doc @typed_fields_doc
  @callback typed_fields(opts :: keyword()) :: [atom()]
  @callback required_fields() :: [atom()]
  @doc @required_fields_doc
  @callback required_fields(opts :: keyword()) :: [atom()]

  alias Domo.ErrorBuilder
  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.ResolvePlanner
  alias Domo.MixProjectHelper
  alias Domo.Raises
  alias Mix.Tasks.Compile.DomoCompiler, as: DomoMixTask

  @doc """
  Uses Domo in the current struct's module to add constructor, validation,
  and reflection functions.

      defmodule Model do
        use Domo

        defstruct [:first_field, :second_field]
        @type t :: %__MODULE__{first_field: atom() | nil, second_field: any() | nil}

        # have added:
        # new/1
        # new_ok/2
        # ensure_type!/1
        # ensure_type_ok/2
        # typed_fields/1
        # required_fields/1
      end

  `use Domo` can be called only within the struct module having
  `t()` type defined because it's used to generate `__MODULE__.TypeEnsurer`
  with validation functions for each field in the definition.

  See details about `t()` type definition in Elixir
  [TypeSpecs](https://hexdocs.pm/elixir/typespecs.html) document.

  The macro collects `t()` type definitions for the `:domo_compiler` which
  generates `TypeEnsurer` modules during the second pass of the compilation
  of the project. Generated validation functions rely on guards appropriate
  for the field types.

  The generated code of each `TypeEnsurer` module can be found
  in `_build/MIX_ENV/domo_generated_code` folder. However, that is for information
  purposes only. The following compilation will overwrite all changes there.

  The macro adds the following functions to the current module, that are the
  facade for the generated `TypeEnsurer` module:
  `new/1`, `new_ok/2`, `ensure_type!/1`, `ensure_type_ok/2`, `typed_fields/1`,
  `required_fields/1`.

  ## Options

    * `ensure_struct_defaults` - if set to `false`, disables the validation of
      default values given with `defstruct/1` to conform to the `t()` type
      at compile time. Default is `true`.

    * `name_of_new_function` - the name of the constructor function added
      to the module. The ok function name is generated automatically from
      the given one by omitting trailing `!` if any, and appending `_ok`.
      Defaults are `new` and `new_ok` appropriately.

    * `unexpected_type_error_as_warning` - if set to `true`, prints warning
      instead of throwing an error for field type mismatch in the raising
      functions. Default is `false`.

    * `remote_types_as_any` - keyword list of type lists by modules that should
      be treated as `any()`. F.e. `[ExternalModule: [:t, :name], OtherModule: :t]`
      Default is `nil`.

  The option value given to the macro overrides one set globally in the
  configuration with `config :domo, option: value`.
  """
  # credo:disable-for-lines:332
  defmacro __using__(opts) do
    Raises.raise_use_domo_out_of_module!(__CALLER__)
    Raises.raise_absence_of_domo_compiler!(Mix.Project.config(), opts, __CALLER__)

    start_resolve_planner()

    global_anys = Application.get_env(:domo, :remote_types_as_any)
    local_anys = Keyword.get(opts, :remote_types_as_any)

    unless is_nil(global_anys) and is_nil(local_anys) do
      collect_types_to_treat_as_any(__CALLER__.module, global_anys, local_anys)
    end

    global_new_func_name = Application.get_env(:domo, :name_of_new_function, :new)
    new_fun_name = Keyword.get(opts, :name_of_new_function, global_new_func_name)

    new_ok_fun_name =
      new_fun_name
      |> Atom.to_string()
      |> String.trim("!")
      |> List.wrap()
      |> Enum.concat(["_ok"])
      |> Enum.join()
      |> String.to_atom()

    type_ensurer = Module.concat(__CALLER__.module, TypeEnsurer)

    long_module = Alias.atom_to_string(__CALLER__.module)
    short_module = long_module |> String.split(".") |> List.last()

    quote do
      Module.register_attribute(__MODULE__, :domo_options, accumulate: false)
      Module.put_attribute(__MODULE__, :domo_options, unquote(opts))

      import Domo, only: [precond: 1]

      @doc """
      #{unquote(@new_doc)}

      ## Examples

          alias #{unquote(long_module)}

          #{unquote(short_module)}.#{unquote(new_fun_name)}(first_field: value1, second_field: value2, ...)
      """
      def unquote(new_fun_name)(enumerable \\ []) do
        skip_ensurance? =
          if ResolvePlanner.compile_time?() do
            Domo._plan_struct_integrity_ensurance(__MODULE__, enumerable)
            true
          else
            false
          end

        struct = struct!(__MODULE__, enumerable)

        unless skip_ensurance? do
          Raises.maybe_raise_add_domo_compiler(__MODULE__)

          {errors, t_precondition_error} = Domo._validate_fields(unquote(type_ensurer), struct, :pretty_error)

          unless Enum.empty?(errors) do
            Raises.raise_or_warn_values_should_have_expected_types(unquote(opts), __MODULE__, errors)
          end

          unless is_nil(t_precondition_error) do
            Raises.raise_or_warn_struct_precondition_should_be_true(unquote(opts), t_precondition_error)
          end
        end

        struct
      end

      @doc """
      #{unquote(@new_ok_doc)}

      ## Examples

          alias #{unquote(long_module)}

          #{unquote(short_module)}.#{unquote(new_ok_fun_name)}(first_field: value1, second_field: value2, ...)
      """
      def unquote(new_ok_fun_name)(enumerable \\ [], opts \\ []) do
        skip_ensurance? =
          if ResolvePlanner.compile_time?() do
            Domo._plan_struct_integrity_ensurance(__MODULE__, enumerable)
            true
          else
            false
          end

        struct = struct(__MODULE__, enumerable)

        if skip_ensurance? do
          {:ok, struct}
        else
          Raises.maybe_raise_add_domo_compiler(__MODULE__)

          {errors, t_precondition_error} = Domo._validate_fields(unquote(type_ensurer), struct, :pretty_error_by_key, opts)

          cond do
            not Enum.empty?(errors) -> {:error, errors}
            not is_nil(t_precondition_error) -> {:error, [t_precondition_error]}
            true -> {:ok, struct}
          end
        end
      end

      @doc """
      #{unquote(@ensure_type_doc)}

      ## Examples

          alias #{unquote(long_module)}

          struct = #{unquote(short_module)}.#{unquote(new_fun_name)}(first_field: value1, second_field: value2, ...)

          #{unquote(short_module)}.ensure_type!(%{struct | first_field: new_value})

          struct
          |> Map.put(:first_field, new_value1)
          |> Map.put(:second_field, new_value2)
          |> #{unquote(short_module)}.ensure_type!()
      """
      def ensure_type!(struct) do
        %name{} = struct

        unless name == __MODULE__ do
          Raises.raise_struct_should_be_passed(__MODULE__, instead_of: name)
        end

        skip_ensurance? =
          if ResolvePlanner.compile_time?() do
            Domo._plan_struct_integrity_ensurance(__MODULE__, Map.from_struct(struct))
            true
          else
            false
          end

        unless skip_ensurance? do
          Raises.maybe_raise_add_domo_compiler(__MODULE__)

          {errors, t_precondition_error} = Domo._validate_fields(unquote(type_ensurer), struct, :pretty_error)

          unless Enum.empty?(errors) do
            Raises.raise_or_warn_values_should_have_expected_types(unquote(opts), __MODULE__, errors)
          end

          unless is_nil(t_precondition_error) do
            Raises.raise_or_warn_struct_precondition_should_be_true(unquote(opts), t_precondition_error)
          end
        end

        struct
      end

      @doc """
      #{unquote(@ensure_type_ok_doc)}

      Options are the same as for `#{unquote(new_ok_fun_name)}/2`.

      ## Examples

          alias #{unquote(long_module)}

          struct = #{unquote(short_module)}.#{unquote(new_fun_name)}(first_field: value1, second_field: value2, ...)

          {:ok, _updated_struct} =
            #{unquote(short_module)}.ensure_type_ok(%{struct | first_field: new_value})

          {:ok, _updated_struct} =
            struct
            |> Map.put(:first_field, new_value1)
            |> Map.put(:second_field, new_value2)
            |> #{unquote(short_module)}.ensure_type_ok()
      """
      def ensure_type_ok(struct, opts \\ []) do
        %name{} = struct

        unless name == __MODULE__ do
          Raises.raise_struct_should_be_passed(__MODULE__, instead_of: name)
        end

        skip_ensurance? =
          if ResolvePlanner.compile_time?() do
            Domo._plan_struct_integrity_ensurance(__MODULE__, Map.from_struct(struct))
            true
          else
            false
          end

        if skip_ensurance? do
          {:ok, struct}
        else
          Raises.maybe_raise_add_domo_compiler(__MODULE__)

          {errors, t_precondition_error} = Domo._validate_fields(unquote(type_ensurer), struct, :pretty_error_by_key, opts)

          cond do
            not Enum.empty?(errors) -> {:error, errors}
            not is_nil(t_precondition_error) -> {:error, [t_precondition_error]}
            true -> {:ok, struct}
          end
        end
      end

      @doc unquote(@typed_fields_doc)
      def typed_fields(opts \\ []) do
        field_kind =
          cond do
            opts[:include_any_typed] && opts[:include_meta] -> :typed_with_meta_with_any
            opts[:include_meta] -> :typed_with_meta_no_any
            opts[:include_any_typed] -> :typed_no_meta_with_any
            true -> :typed_no_meta_no_any
          end

        apply(unquote(type_ensurer), :fields, [field_kind])
      end

      @doc unquote(@required_fields_doc)
      def required_fields(opts \\ []) do
        field_kind = if opts[:include_meta], do: :required_with_meta, else: :required_no_meta
        apply(unquote(type_ensurer), :fields, [field_kind])
      end

      @before_compile {Raises, :raise_not_in_a_struct_module!}
      @before_compile {Raises, :raise_no_type_t_defined!}
      @before_compile {Domo, :_plan_struct_defaults_ensurance}

      @after_compile {Domo, :_collect_types_for_domo_compiler}
    end
  end

  defp start_resolve_planner do
    project = MixProjectHelper.global_stub() || Mix.Project
    plan_path = DomoMixTask.manifest_path(project, :plan)
    preconds_path = DomoMixTask.manifest_path(project, :preconds)

    {:ok, _pid} = ResolvePlanner.ensure_started(plan_path, preconds_path)

    plan_path
  end

  defp get_plan_path do
    project = MixProjectHelper.global_stub() || Mix.Project
    DomoMixTask.manifest_path(project, :plan)
  end

  defp collect_types_to_treat_as_any(module, global_anys, local_anys) do
    plan_path = get_plan_path()

    unless is_nil(global_anys) do
      global_anys_map = cast_keyword_to_map_of_lists_by_module(global_anys)
      ResolvePlanner.keep_global_remote_types_to_treat_as_any(plan_path, global_anys_map)
    end

    unless is_nil(local_anys) do
      local_anys_map = cast_keyword_to_map_of_lists_by_module(local_anys)
      ResolvePlanner.keep_remote_types_to_treat_as_any(plan_path, module, local_anys_map)
    end
  end

  defp cast_keyword_to_map_of_lists_by_module(kw_list) do
    kw_list
    |> Enum.map(fn {key, value} -> {Module.concat(Elixir, key), List.wrap(value)} end)
    |> Enum.into(%{})
  end

  @doc false
  def _validate_fields(type_ensurer, struct, err_fun, opts \\ []) do
    maybe_filter_precond_errors = Keyword.get(opts, :maybe_filter_precond_errors, false)

    errors =
      Enum.reduce(Map.from_struct(struct), [], fn key_value, errors ->
        case apply(type_ensurer, :ensure_field_type, [key_value]) do
          {:error, _} = error ->
            [apply(ErrorBuilder, err_fun, [error, maybe_filter_precond_errors]) | errors]

          _ ->
            errors
        end
      end)

    t_precondition_error =
      if Enum.empty?(errors) do
        case apply(type_ensurer, :t_precondition, [struct]) do
          {:error, _} = error -> apply(ErrorBuilder, err_fun, [error, maybe_filter_precond_errors])
          :ok -> nil
        end
      end

    {errors, t_precondition_error}
  end

  @doc false
  def _collect_types_for_domo_compiler(env, bytecode) do
    plan_path = get_plan_path()

    :ok = ResolvePlanner.keep_module_environment(plan_path, env.module, env)

    {:"::", _, [{:t, _, _}, {:%, _, [_module_name, {:%{}, _, field_type_list}]}]} =
      bytecode
      |> Code.Typespec.fetch_types()
      |> elem(1)
      |> Enum.find_value(fn
        {:type, {:t, _, _} = t} -> t
        _ -> nil
      end)
      |> Code.Typespec.type_to_quoted()

    if Enum.empty?(field_type_list) do
      ResolvePlanner.plan_empty_struct(plan_path, env.module)
    else
      Enum.each(field_type_list, fn {field, quoted_type} ->
        :ok ==
          ResolvePlanner.plan_types_resolving(
            plan_path,
            env.module,
            field,
            quoted_type
          )
      end)
    end
  end

  @doc false
  def _plan_struct_defaults_ensurance(env) do
    global_ensure_struct_defaults = Application.get_env(:domo, :ensure_struct_defaults, true)

    opts = Module.get_attribute(env.module, :domo_options, [])
    ensure_struct_defaults = Keyword.get(opts, :ensure_struct_defaults, global_ensure_struct_defaults)

    if ensure_struct_defaults do
      _do_plan_struct_defaults_ensurance(env)
    end
  end

  def _do_plan_struct_defaults_ensurance(env) do
    plan_path = get_plan_path()

    struct = Module.get_attribute(env.module, :__struct__) || Module.get_attribute(env.module, :struct)
    enforce_keys = Module.get_attribute(env.module, :enforce_keys) || []
    keys_to_drop = [:__struct__ | enforce_keys]

    defaults =
      struct
      |> Map.from_struct()
      |> Enum.reject(fn {key, _value} -> key in keys_to_drop end)
      |> Enum.sort_by(fn {key, _value} -> key end)

    :ok ==
      ResolvePlanner.plan_struct_defaults_ensurance(
        plan_path,
        env.module,
        defaults,
        to_string(env.file),
        env.line
      )
  end

  @doc false
  def _plan_struct_integrity_ensurance(module, enumerable) do
    plan_path = get_plan_path()

    {:current_stacktrace, calls} = Process.info(self(), :current_stacktrace)

    {_, _, _, file_line} = Enum.find(calls, Enum.at(calls, 3), fn {_, module, _, _} -> module == :__MODULE__ end)

    :ok ==
      ResolvePlanner.plan_struct_integrity_ensurance(
        plan_path,
        module,
        enumerable,
        to_string(file_line[:file]),
        file_line[:line]
      )
  end

  @doc """
  Defines a precondition function for a field's type or the struct's type.

  The `type_fun` argument is one element `[type: fun]` keyword list where
  `type` is the name of the type defined with the `@type` attribute
  and `fun` is a single argument user-defined precondition function.

  The precondition function validates the value of the given type to match
  a specific format or to fulfil a set of invariants for the field's type
  or struct's type respectfully.

  The macro should be called with a type in the same module where the `@type`
  definition is located. If that is no fulfilled, f.e., when the previously
  defined type has been renamed, the macro raises an `ArgumentError`.

      defstruct [id: "I-000", amount: 0, limit: 15]

      @type id :: String.t()
      precond id: &validate_id/1

      defp validate_id(id), do: match?(<<"I-", _::8*3>>, id)

      @type t :: %__MODULE__{id: id(), amount: integer(), limit: integer()}
      precond t: &validate_invariants/1

      defp validate_invariants(s) do
        cond do
          s.amount >= s.limit ->
            {:error, "Amount \#{s.amount} should be less then limit \#{s.limit}."}

          true ->
            :ok
        end
      end

  `TypeEnsurer` module generated by Domo calls the precondition function with
  value of the valid type. Precondition function should return the following
  values: `true | false | :ok | {:error, any()}`.

  In case of `true` or `:ok` return values `TypeEnsurer` finishes
  the validation of the field with ok.
  For the `false` return value, the `TypeEnsurer` generates an error message
  referencing the failed precondition function. And for the `{:error, message}`
  return value, it passes the `message` as one of the errors for the field value.
  `message` can be of any shape.

  Macro adds the `__precond__/2` function to the current module that routes
  a call to the user-defined function. The added function should be called
  only by Domo modules.

  Attaching a precondition function to the type via this macro can be helpful
  to keep the same level of consistency across the domains modelled
  with structs sharing the given type.
  """
  defmacro precond([{type_name, {fn?, _, _} = fun}] = _type_fun)
           when is_atom(type_name) and fn? in [:&, :fn] do
    module = __CALLER__.module

    unless Module.has_attribute?(module, :domo_precond) do
      Module.register_attribute(module, :domo_precond, accumulate: true)
      Module.put_attribute(module, :after_compile, {Domo, :_plan_precond_checks})
    end

    fun_as_string = Macro.to_string(fun)
    precond_name_description = {type_name, fun_as_string}
    Module.put_attribute(module, :domo_precond, precond_name_description)

    quote do
      def __precond__(unquote(type_name), value) do
        apply(unquote(fun), [value])
      end
    end
  end

  defmacro precond(_arg) do
    Raises.raise_precond_arguments()
  end

  @doc false
  def _plan_precond_checks(env, bytecode) do
    module_type_names =
      bytecode
      |> Code.Typespec.fetch_types()
      |> elem(1)
      |> Enum.map(fn {:type, {name, _, _}} -> name end)

    module = env.module
    precond_name_description = Module.get_attribute(module, :domo_precond)

    precond_type_names =
      precond_name_description
      |> Enum.unzip()
      |> elem(0)

    missing_type = any_missing_type(precond_type_names, module_type_names)

    if missing_type do
      Raises.raise_nonexistent_type_for_precond(missing_type)
    end

    # precond macro can be called via import Domo, so need to start resolve planner
    plan_path = start_resolve_planner()
    :ok = ResolvePlanner.plan_precond_checks(plan_path, module, precond_name_description)
  end

  defp any_missing_type(precond_type_names, module_type_names) do
    precond_type_names = MapSet.new(precond_type_names)
    module_type_names = MapSet.new(module_type_names)

    precond_type_names
    |> MapSet.difference(module_type_names)
    |> MapSet.to_list()
    |> List.first()
  end
end
