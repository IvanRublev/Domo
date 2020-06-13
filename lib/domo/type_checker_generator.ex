defmodule Domo.TypeCheckerGenerator do
  @moduledoc false

  @doc false
  @spec stacktrace() :: [any]
  def stacktrace() do
    {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)

    stacktrace
    |> List.delete_at(0)
    |> List.delete_at(0)
  end

  @doc false
  def module(fields_kw_spec, caller_env) do
    quote do
      defmodule TypeChecker do
        @moduledoc false

        @domo_options Module.get_attribute(unquote(caller_env.module), :domo_options)

        @type fn_new_argument ::
                [unquote_splicing(fields_kw_spec)] | %{unquote_splicing(fields_kw_spec)}
        @type fn_new_field_error :: %{field: atom, value: any, type: String.t()}

        @spec __survive_argument_error((() -> struct())) ::
                {:ok, struct()} | {:error, {:key_err, String.t()}}
        def __survive_argument_error(struct_generator) do
          try do
            {:ok, struct_generator.()}
          rescue
            err in [ArgumentError] -> {:error, {:key_err, err.message}}
          end
        end

        @spec __format_mistyped_construction_error([fn_new_field_error()], String.t()) ::
                String.t()
        def __format_mistyped_construction_error(list, call_site) do
          "Can't construct %#{inspect(unquote(caller_env.module))}{...}"
          |> Kernel.<>(if String.length(call_site) == 0, do: "", else: " with " <> call_site)
          |> Kernel.<>("\n")
          |> Kernel.<>(__format_value_type_error(list))
        end

        @spec __format_value_type_error([fn_new_field_error()], padding: boolean) :: String.t()
        def __format_value_type_error(list, opts \\ [padding: true]) do
          list
          |> Enum.map(&"Unexpected value type for the field #{inspect(&1.field)}. \
The value #{inspect(&1.value)} doesn't match the #{&1.type} type.")
          |> Enum.map(&(if(true == opts[:padding], do: "    ", else: "") <> &1))
          |> Enum.join("\n")
        end

        @spec __struct_or_mistyped_fields_err(struct(), (() -> String.t())) ::
                {:ok, struct()} | {:error, {:value_err, String.t()}}
        def __struct_or_mistyped_fields_err(struct, call_site_fn) do
          case __mistyped_fields(Map.from_struct(struct)) do
            [] ->
              {:ok, struct}

            list ->
              {:error, {:value_err, __format_mistyped_construction_error(list, call_site_fn.())}}
          end
        end

        @spec __raise_mistyped_fields_if_needed(struct(), (() -> String.t()), [any]) ::
                struct()
        def __raise_mistyped_fields_if_needed(struct, call_site_fn, stacktrace) do
          case __mistyped_fields(Map.from_struct(struct)) do
            [] ->
              struct

            list ->
              __cast_to_warning_if_configured(
                fn ->
                  reraise(
                    ArgumentError,
                    __format_mistyped_construction_error(list, call_site_fn.()),
                    stacktrace
                  )
                end,
                struct
              )
          end
        end

        @spec __cast_to_warning_if_configured(function, any) :: any
        def __cast_to_warning_if_configured(raising_fn, return_value) do
          error_as_warning =
            case Keyword.fetch(@domo_options, :unexpected_type_error_as_warning) do
              {:ok, value} -> value
              _ -> Application.get_env(:domo, :unexpected_type_error_as_warning, false)
            end

          if error_as_warning do
            try do
              raising_fn.()
            rescue
              err -> IO.warn(inspect(err))
            end

            return_value
          else
            raising_fn.()
          end
        end

        @spec __mistyped_fields(fn_new_argument()) :: [fn_new_field_error()]
        def __mistyped_fields(enumerable) do
          Enum.filter(Enum.map(enumerable, &__field_error/1), &(not is_nil(&1)))
        end

        @spec __field_error({atom, any}) :: fn_new_field_error() | nil
        unquote(quoted_field_error_funs(fields_kw_spec, caller_env))
        def __field_error({_unknown_field, _value}), do: nil
      end
    end
  end

  defp quoted_field_error_funs(fields_kw_spec, caller_env) do
    fields_kw_spec
    |> Enum.map(fn {field, type} -> {field, Macro.escape(type), Macro.to_string(type)} end)
    |> Enum.map(&quoted_field_error(&1, caller_env))
  end

  defp quoted_field_error({field, type_esc, type_str}, caller_env) do
    caller_env = Macro.escape(caller_env)

    quote do
      def __field_error({unquote(field) = name, value}) do
        case Domo.TypeContract.valid?(value, unquote(type_esc), unquote(caller_env)) do
          true -> nil
          false -> %{field: name, value: value, type: unquote(type_str)}
        end
      end
    end
  end
end
