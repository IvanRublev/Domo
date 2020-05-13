defmodule Domo.RuntimeChecksTest do
  use ExUnit.Case, async: true

  defp spec_to_strings(bytecode) do
    bytecode
    |> specs()
    |> Enum.flat_map(fn {{fn_name, _}, fns} ->
      Enum.map(fns, &{fn_name, Macro.to_string(Code.Typespec.spec_to_quoted(fn_name, &1))})
    end)
  end

  defp specs(bytecode) do
    bytecode
    |> Code.Typespec.fetch_specs()
    |> elem(1)
    |> Enum.sort()
  end

  defp types_to_strings(bytecode) do
    bytecode
    |> types()
    |> Enum.map(fn {_, {type_name, _, _} = type} ->
      {type_name, Macro.to_string(Code.Typespec.type_to_quoted(type))}
    end)
  end

  defp types(bytecode) do
    bytecode
    |> Code.Typespec.fetch_types()
    |> elem(1)
    |> Enum.sort()
  end

  setup_all do
    {:module, _, multi_field_bytecode, _} =
      defmodule SpecTestOrder do
        use Domo

        deftag Id, for_type: String.t()
        deftag Note, for_type: :none | String.t()

        deftag Quantity do
          for_type __MODULE__.Units.t() | __MODULE__.Kilograms.t()

          deftag Units do
            for_type __MODULE__.Packages.t() | __MODULE__.Boxes.t()

            deftag Packages, for_type: integer
            deftag Boxes, for_type: integer
          end

          deftag Kilograms, for_type: float
        end

        typedstruct do
          field :id, Id.t()
          field :note, Note.t()
          field :quantity, Quantity.t()
          field :comment, String.t()
          field :version, integer
        end
      end

    {:module, _, one_field_bytecode, _} =
      defmodule SpecTestOrder10 do
        use Domo

        typedstruct do
          field :one_key, :none | float | integer
        end
      end

    {:module, _, no_fields_bytecode, _} =
      defmodule SpecTestOrder20 do
        use Domo

        typedstruct do
        end
      end

    {:ok,
     %{
       multi_field_bytecode: multi_field_bytecode,
       one_field_bytecode: one_field_bytecode,
       no_fields_bytecode: no_fields_bytecode
     }}
  end

  describe "new/1 constructor functions added to module should have a spec with" do
    test "argument of fn_new_argument type and return of the result tuple", %{
      multi_field_bytecode: bytecode
    } do
      {:ok, new_spec} = Keyword.fetch(spec_to_strings(bytecode), :new)

      assert "new(fn_new_argument()) :: {:ok, t()} | {:error, {:key_err | :value_err, String.t()}}" ==
               new_spec
    end
  end

  describe "new!/1 constructor functions added to module should have a spec with" do
    test "argument of fn_new_argument type and return of t()", %{multi_field_bytecode: bytecode} do
      {:ok, new_spec} = Keyword.fetch(spec_to_strings(bytecode), :new!)

      assert "new!(fn_new_argument()) :: t()" == new_spec
    end
  end

  describe "new functions argument type should be" do
    test "a enum with values of specified filed types", %{multi_field_bytecode: bytecode} do
      {:ok, new_arg_spec} = Keyword.fetch(types_to_strings(bytecode), :fn_new_argument)

      assert "fn_new_argument() :: [id: Domo.RuntimeChecksTest.SpecTestOrder.Id.t(), \
note: Domo.RuntimeChecksTest.SpecTestOrder.Note.t(), \
quantity: Domo.RuntimeChecksTest.SpecTestOrder.Quantity.t(), \
comment: String.t(), version: integer()] | \
%{id: Domo.RuntimeChecksTest.SpecTestOrder.Id.t(), \
note: Domo.RuntimeChecksTest.SpecTestOrder.Note.t(), \
quantity: Domo.RuntimeChecksTest.SpecTestOrder.Quantity.t(), \
comment: String.t(), version: integer()}" == new_arg_spec
    end

    test "one field enum in case", %{one_field_bytecode: bytecode} do
      {:ok, new_arg_spec} = Keyword.fetch(types_to_strings(bytecode), :fn_new_argument)

      assert "fn_new_argument() :: [{:one_key, :none | float() | integer()}] | \
%{one_key: :none | float() | integer()}" == new_arg_spec
    end

    test "empty enum if no filelds are specified", %{no_fields_bytecode: bytecode} do
      {:ok, new_arg_spec} = Keyword.fetch(types_to_strings(bytecode), :fn_new_argument)

      assert "fn_new_argument() :: [] | %{}" == new_arg_spec
    end
  end

  describe "put/3 function(s) added to module should have specs with" do
    test "appropriate field and value type each", %{multi_field_bytecode: bytecode} do
      [sp1, sp2, sp3, sp4, sp5] =
        Enum.reverse(
          Enum.reduce(spec_to_strings(bytecode), [], fn
            {:put, spec}, acc -> [spec | acc]
            _, acc -> acc
          end)
        )

      assert sp1 == "put(t(), :id, Domo.RuntimeChecksTest.SpecTestOrder.Id.t()) \
:: {:ok, t()} | {:error, {:unexpected_struct | :key_err | :value_err, String.t()}}"
      assert sp2 == "put(t(), :note, Domo.RuntimeChecksTest.SpecTestOrder.Note.t()) \
:: {:ok, t()} | {:error, {:unexpected_struct | :key_err | :value_err, String.t()}}"
      assert sp3 == "put(t(), :quantity, Domo.RuntimeChecksTest.SpecTestOrder.Quantity.t()) \
:: {:ok, t()} | {:error, {:unexpected_struct | :key_err | :value_err, String.t()}}"
      assert sp4 == "put(t(), :comment, String.t()) :: {:ok, t()} \
| {:error, {:unexpected_struct | :key_err | :value_err, String.t()}}"
      assert sp5 == "put(t(), :version, integer()) :: {:ok, t()} \
| {:error, {:unexpected_struct | :key_err | :value_err, String.t()}}"
    end

    test "one field in case", %{one_field_bytecode: bytecode} do
      {:ok, sp1} = Keyword.fetch(spec_to_strings(bytecode), :put)

      assert "put(t(), :one_key, :none | float() | integer()) :: {:ok, t()} \
| {:error, {:unexpected_struct | :key_err | :value_err, String.t()}}" = sp1
    end
  end

  describe "put!/3 function(s) added to module should have specs with" do
    test "appropriate field and value type each", %{multi_field_bytecode: bytecode} do
      [sp1, sp2, sp3, sp4, sp5] =
        Enum.reverse(
          Enum.reduce(spec_to_strings(bytecode), [], fn
            {:put!, spec}, acc -> [spec | acc]
            _, acc -> acc
          end)
        )

      assert sp1 == "put!(t(), :id, Domo.RuntimeChecksTest.SpecTestOrder.Id.t()) :: t()"
      assert sp2 == "put!(t(), :note, Domo.RuntimeChecksTest.SpecTestOrder.Note.t()) :: t()"

      assert sp3 ==
               "put!(t(), :quantity, Domo.RuntimeChecksTest.SpecTestOrder.Quantity.t()) :: t()"

      assert sp4 == "put!(t(), :comment, String.t()) :: t()"
      assert sp5 == "put!(t(), :version, integer()) :: t()"
    end

    test "one field in case", %{one_field_bytecode: bytecode} do
      {:ok, sp1} = Keyword.fetch(spec_to_strings(bytecode), :put!)

      assert "put!(t(), :one_key, :none | float() | integer()) :: t()" = sp1
    end
  end

  test "merge(!)/2 functions added to module should have spec with general arguments", %{
    one_field_bytecode: bytecode
  } do
    {:ok, sp1} = Keyword.fetch(spec_to_strings(bytecode), :merge!)
    {:ok, sp2} = Keyword.fetch(spec_to_strings(bytecode), :merge)

    assert "merge!(t(), keyword() | map()) :: t()" = sp1

    assert "merge(t(), keyword() | map()) :: {:ok, t()} | {:error, {:unexpected_struct | :value_err, String.t()}}" =
             sp2
  end
end
