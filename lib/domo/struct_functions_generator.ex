defmodule Domo.StructFunctionsGenerator do
  @moduledoc """
  A module to generate public functions in a struct
  """

  alias Domo.TypeCheckerGenerator

  @doc false
  def quoted_new_funs(fields_spec, caller_module) do
    quote location: :keep do
      alias unquote(caller_module).TypeChecker

      @spec new!([unquote_splicing(fields_spec)] | %{unquote_splicing(fields_spec)}) :: t()
      def new!(enumerable) do
        TypeChecker.__raise_mistyped_fields_if_needed(
          struct!(__MODULE__, enumerable),
          fn ->
            "new!(#{inspect(enumerable)})"
          end,
          TypeCheckerGenerator.stacktrace()
        )
      end

      @spec new([unquote_splicing(fields_spec)] | %{unquote_splicing(fields_spec)}) ::
              {:ok, t()} | {:error, {:key_err | :value_err, String.t()}}
      def new(enumerable) do
        with {:ok, s} <-
               TypeChecker.__survive_argument_error(fn ->
                 struct!(unquote(caller_module), enumerable)
               end),
             {:ok, s} = res <-
               TypeChecker.__struct_or_mistyped_fields_err(s, fn ->
                 "new(#{inspect(enumerable)})"
               end) do
          res
        else
          err -> err
        end
      end

      defoverridable new!: 1, new: 1
    end
  end

  @doc false
  def quoted_merge_funs(fields_spec) when fields_spec == [], do: nil

  def quoted_merge_funs(fields_spec) do
    struct_keys = Keyword.keys(fields_spec)

    quote location: :keep do
      @spec merge(t(), keyword() | map()) ::
              {:ok, t()} | {:error, {:unexpected_struct | :value_err, String.t()}}
      def merge(%__MODULE__{} = s, enumerable) do
        case __filter_mistyped_fields(enumerable) do
          [] ->
            {:ok, struct(s, enumerable)}

          list ->
            {:error, {:value_err, TypeChecker.__format_value_type_error(list, padding: false)}}
        end
      end

      def merge(%name{}, _enum) do
        {:error, {:unexpected_struct, "#{inspect(__MODULE__)} structure was expected \
as the first argument and #{inspect(name)} was received."}}
      end

      @spec merge!(t(), keyword() | map()) :: t()
      def merge!(%__MODULE__{} = s, enumerable) do
        case __filter_mistyped_fields(enumerable) do
          [] ->
            struct(s, enumerable)

          list ->
            reraise(ArgumentError, TypeChecker.__format_value_type_error(list, padding: false), TypeCheckerGenerator.stacktrace())
        end
      end

      def merge!(%name{}, _enum),
        do: reraise(ArgumentError, "#{inspect(__MODULE__)} structure was expected \
as the first argument and #{inspect(name)} was received.", TypeCheckerGenerator.stacktrace())

      @spec __filter_mistyped_fields(keyword() | map()) :: [TypeChecker.fn_new_field_error()] | []
      defp __filter_mistyped_fields(enumerable) do
        enumerable
        |> Enum.filter(fn {key, _value} -> Enum.member?(unquote(struct_keys), key) end)
        |> Enum.into(%{})
        |> TypeChecker.__mistyped_fields()
      end

      defoverridable merge!: 2, merge: 2
    end
  end

  @doc false
  def quoted_put_funs(fields_spec) when fields_spec == [], do: nil

  def quoted_put_funs(fields_spec) do
    fields_spec
    |> Enum.map(fn {key, type} -> quoted_puts(key, type) end)
    |> List.insert_at(-1, quoted_put_bang_raise_nonpresent_key())
    |> List.insert_at(-1, quoted_put_bang_raise_struct_name())
    |> List.insert_at(-1, quoted_put_err_nonpresent_key())
    |> List.insert_at(-1, quoted_put_err_struct_name())
    |> List.insert_at(-1, quote(do: defoverridable(put!: 3, put: 3)))
  end

  defp quoted_puts(key, type) do
    quote location: :keep do
      @spec put!(t(), unquote(key), unquote(type)) :: t()
      def put!(%__MODULE__{} = s, unquote(key), value) do
        case TypeChecker.__field_error({unquote(key), value}) do
          %{} = err ->
            reraise(ArgumentError, TypeChecker.__format_value_type_error([err], padding: false), TypeCheckerGenerator.stacktrace())

          nil ->
            Map.replace!(s, unquote(key), value)
        end
      end

      @spec put(t(), unquote(key), unquote(type)) ::
              {:ok, t()}
              | {:error, {:unexpected_struct | :key_err | :value_err, String.t()}}
      def put(%__MODULE__{} = s, unquote(key), value) do
        case TypeChecker.__field_error({unquote(key), value}) do
          %{} = err ->
            {:error, {:value_err, TypeChecker.__format_value_type_error([err], padding: false)}}

          nil ->
            {:ok, Map.replace!(s, unquote(key), value)}
        end
      end
    end
  end

  defp quoted_put_bang_raise_nonpresent_key do
    quote do
      def put!(%__MODULE__{} = s, key, val), do: Map.replace!(s, key, val)
    end
  end

  defp quoted_put_bang_raise_struct_name do
    quote do
      def put!(%name{}, _key, _val),
        do: reraise(ArgumentError, "#{inspect(__MODULE__)} structure was expected \
as the first argument and #{inspect(name)} was received.", TypeCheckerGenerator.stacktrace())
    end
  end

  defp quoted_put_err_nonpresent_key do
    quote do
      def put(%__MODULE__{} = s, key, val) do
        {:error, {:key_err, "no #{inspect(key)} key found in the struct."}}
      end
    end
  end

  defp quoted_put_err_struct_name do
    quote do
      def put(%name{}, _key, _val) do
        {:error, {:unexpected_struct, "#{inspect(__MODULE__)} structure was expected \
as the first argument and #{inspect(name)} was received."}}
      end
    end
  end
end
