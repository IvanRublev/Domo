defmodule Domo.RuntimeChecksTest do
  use ExUnit.Case

  defp specs(bytecode) do
    bytecode
    |> Code.Typespec.fetch_specs()
    |> elem(1)
    |> Enum.sort()
  end

  defp spec_to_strings(bytecode) do
    bytecode
    |> specs()
    |> Enum.flat_map(fn {{fn_name, _}, fns} ->
      Enum.map(fns, &Macro.to_string(Code.Typespec.spec_to_quoted(fn_name, &1)))
    end)
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

  describe "new!/1 constructor function added to module should have spec with" do
    test "map's values of specified filed types", %{multi_field_bytecode: bytecode} do
      [new_spec | _] = spec_to_strings(bytecode)

      assert new_spec ==
               "new!(map :: %{id: Domo.RuntimeChecksTest.SpecTestOrder.Id.t(), note: Domo.RuntimeChecksTest.SpecTestOrder.Note.t(), quantity: Domo.RuntimeChecksTest.SpecTestOrder.Quantity.t(), comment: String.t(), version: integer()}) :: t()"
    end

    test "one field map in case", %{one_field_bytecode: bytecode} do
      [new_spec | _] = spec_to_strings(bytecode)

      assert new_spec ==
               "new!(map :: %{one_key: :none | float() | integer()}) :: t()"
    end

    test "empty map if no filelds specified", %{no_fields_bytecode: bytecode} do
      [new_spec | _] = spec_to_strings(bytecode)

      assert new_spec ==
               "new!(map :: %{}) :: t()"
    end
  end

  describe "put!/3 function(s) added to module should have specs with" do
    test "appropriate field and value type each", %{multi_field_bytecode: bytecode} do
      [_, sp1, sp2, sp3, sp4, sp5 | _] = spec_to_strings(bytecode)

      assert sp1 == "put!(s :: t(), :id, Domo.RuntimeChecksTest.SpecTestOrder.Id.t()) :: t()"
      assert sp2 == "put!(s :: t(), :note, Domo.RuntimeChecksTest.SpecTestOrder.Note.t()) :: t()"

      assert sp3 ==
               "put!(s :: t(), :quantity, Domo.RuntimeChecksTest.SpecTestOrder.Quantity.t()) :: t()"

      assert sp4 == "put!(s :: t(), :comment, String.t()) :: t()"
      assert sp5 == "put!(s :: t(), :version, integer()) :: t()"
    end

    test "one field in case", %{one_field_bytecode: bytecode} do
      [_, sp1 | _] = spec_to_strings(bytecode)

      assert sp1 == "put!(s :: t(), :one_key, :none | float() | integer()) :: t()"
    end
  end

  test "put!/3 functions should Not be added to module if no fields specified", %{
    no_fields_bytecode: bytecode
  } do
    assert [_] = spec_to_strings(bytecode)
  end
end
