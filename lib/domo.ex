defmodule Domo do
  @moduledoc """
  Domo is a library to model a business domain with type-safe structs and
  composable tagged tuples.

  It's a library to define what piece of data is what and make a run-time type
  verification to cover one's back.

  The library aims for two goals:

    * to model domain entities with structs and model value objects
      with tagged tuples

    * to allow only valid states for structs by ensuring that their fileds
      match the defined struct's type

  The input value range checking is on the author of the concrete application.
  The Domo library can only ensure that the struct field value matches Elixir data
  type or another struct according to given type definitions.

  ## Rationale

  A common way to validate that input data is of the model struct's type
  is to do it within a constructor function like the following:

      defmodule User do
        type t :: %__MODULE__{
          id: integer,
          name: String.t(),
          post_address: :not_given | String.t(), default: :not_given
        }

        defstruct [:id, :name, :post_address]

        def new(id: id, name: name, post_address: post_address)
          when is_integer(id) and
            is_binary(name) and
            (post_address == :not_given or is_binary(post_address)) do
          struct!(__MODULE__, id: id, name: name)
        end
      end

  The code written above repeats for almost every entity in the application.
  And it'd be great to make it generated automatically, reducing the structure
  definition to the minimal and declarative.

  One way to do this is with the Domo library that plays nicely together
  with [TypedStruct](https://hexdocs.pm/typed_struct/) like the following:

      defmodule User do
        use Domo
        use TypedStruct

        typedstruct enforce: true do
          field :id, integer
          field :name, String.t()
          field :post_address, :not_given | String.t(), default: :not_given
        end
      end

  Thanks to the `typedstruct` macro from the same named library the type
  and struct definitions are in the module.

  What the Domo adds on top are the constructor function `new/1` and
  the `ensure_type!/1` function. These functions ensure that arguments
  are of the field types otherwise raising the `ArgumentError` exception.

  Domo adds `new_ok/1` and `ensure_type_ok/1` versions returning ok-error
  tuple too.

  The construction with automatic type ensurance of the User struct can
  be as immediate as that:

      User.new(id: 1, name: "John")
      %User{id: 1, name: "John", post_address: :not_given}

      User.new(id: 2, name: nil, post_address: 3)
      ** (ArgumentError) Can't construct %User{...} with new!([id: 2, name: nil, post_address: 3])
          Unexpected value type for the field :name. The value nil doesn't match the String.t() type.
          Unexpected value type for the field :post_address. The value 3 doesn't match the :not_given | String.t() type.

  After the modification of the existing struct its type can be ensured
  like the following:

      user
      |> User.struct!(name: "John Bongiovi")
      |> User.ensure_type!()
      %User{id: 1, name: "John Bongiovi", post_address: :not_given}

  ## How it works

  For each `MyModule` struct Domo library generates a `MyModule.TypeEnsurer` at
  the compile time. The latter verifies that the given fields matches the
  type of MyModule and is used by `new/1` constructor and other functions.

  If the field is of the struct type that uses Domo as well, then the ensurance
  of the field's value delegates to the `TypeEnsurer` of that struct.

  Domo library uses :domo compiler to generate `TypeEnsurer` modules code. See
  the mix.exs in example_app for the compilers configuration.

  The generated code can always be found in the `_build/ENV/domo_generated_code`
  directory. That code is compiled during the project compilation automatically.

  ## Depending types tracking

  Suppose the given structure field's type depends on a type defined in another module.
  And that module changes, then Domo recompiles the depending structure automatically
  to update its `TypeEnsurer` module to keep type validation correct.

  ## Further refinement with tags

  So far, so good. Let's say that we have another entity in our
  system - the Order that has an identifier as well. Both ids for User
  and Order structs are of the integer type. How to ensure that we don't mix
  them up throughout the various execution paths in the application?
  One way to do that is to attach an appropriate tag to each of the ids
  with [tagged tuple](https://erlang.org/doc/getting_started/seq_prog.html#tuples) like the following:

      defmodule User do
        use Domo
        use TypedStruct

        defmodule Id, do: @type t :: {__MODULE__, integer}

        typedstruct enforce: true do
          field :id, Id.t()
          field :name, String.t()
          field :post_address, :none | String.t(), default: :none
        end
      end

      defmodule Order do
        use Domo
        use TypedStruct

        defmodule Id, do: @type t :: {__MODULE__, integer}

        typedstruct enforce: true do
          field :id, Id.t()
          field :name, String.t()
        end
      end

      User.new(id: {User.Id, 152}, name: "Bob")
      %User{id: {User.Id, 152}, name: "Bob", post_address: :none}

      Order.new(id: {Order.Id, 153}, name: "Fruits")
      %Order{id: {Order.Id, 153}, name: "Fruits"}

      User.new(id: {Order.Id, 153}, name: "Fruits")
      ** (ArgumentError) Can't construct %User{...} with new!([id: {Order.Id, 153}, name: "Fruits"])
          Unexpected value type for the field :id. The value {Order.Id, 153} doesn't match the {User.Id, integer} type.

  ### Third dimension for structures with tag chains and ---/2 operator 🍿

  Let's say one of the business requirements is to register the quantity
  of the Order in units or kilograms. That means that the structure's quantity
  field value can be integer or float. It'd be great to keep the kind
  of quantity alongside the value for the sake of local reasoning in different
  parts of the application. One possible way to do that is to use tag chains
  like that:

      defmodule Order do
        use Domo

        defmodule Id, do: @type t :: {__MODULE__, integer}

        deftag Quantity do
          @type t :: {__MODULE__, __MODULE__.Units.t() | __MODULE__.Kilograms.t()}

          defmodule Kilograms, do: @type(t :: {__MODULE__, float()})
          defmodule Units, do: @type(t :: {__MODULE__, integer()})
        end

        typedstruct do
          field :id, Id.t()
          field :name, String.t()
          field :quantity, Quantity.t()
        end
      end

      alias Order.{Id, Quantity}
      alias Order.Quantity.{Kilograms, Units}

      Order.new(id: {Id, 158}, name: "Fruits", quantity: {Quantity, {Kilograms, 12.5}})
      %Order{
        id: {Order.Id, 158},
        name: "Fruits",
        quantity: {Order.Quantity, {Order.Quantity.Kilograms, 12.5}}
      }

      Order.new(id: {Id, 159}, name: "Bananas", quantity: {Quantity, "5 boxes"})
      ** (ArgumentError) Can't construct %Order{...} with new!([id: {Order.Id, 159}, name: "Bananas", quantity: {Order.Quantity, "5 boxes"}])
          Unexpected value type for the field :quantity. The value {Order.Quantity, "5 boxes"} doesn't match the Quantity.t() type.

  In the example above the construction with invalid quantity raises
  the exception.

  To remove extra brackets from the tag chain definition, one can use the `---/2`
  operator from the `Domo.TaggedTuple` module. Then one can rewrite the above
  example as that:

      use Domo.TaggedTuple
      alias Order.{Id, Quantity}
      alias Order.Quantity.{Kilograms, Units}

      Order.new(id: Id --- 158, name: "Fruits", quantity: Quantity --- Kilograms --- 12.5)
      %Order{
        id: {Order.Id, 158},
        name: "Fruits",
        quantity: {Order.Quantity, {Order.Quantity.Kilograms, 12.5}}
      }

  It's possible to use `---/2` even in pattern matchin like the following:

      def to_string(%Order{quantity: Quantity --- Kilograms --- kilos}), do: to_string(kilos) <> "kg"
      def to_string(%Order{quantity: Quantity --- Units --- kilos}), do: to_string(kilos) <> " units"

  ## Usage

  ### Setup

  To use Domo in your project, add this to your `mix.exs` dependencies:

      {:domo, "~> #{Mix.Project.config()[:version]}"}

  And the folowing line to the compilers:

      compilers: Mix.compilers() ++ [:domo],

  To avoid `mix format` putting extra parentheses around macro calls,
  you can add to your `.formatter.exs`:

      [
        ...,
        import_deps: [:domo]
      ]

  ### General usage

  #### Define a structure

  To describe a structure with field value contracts, use Domo, then define
  your struct and its type.

      defmodule Wonder do
        use Domo

        @typedoc "A world wonder. Ancient or contemporary."
        @enforce_keys [:id]
        defstruct [:id, :name]

        @type t :: %__MODULE__{id: integer, name: nil | String.t()}
      end

  The generated structure has `new/1`, `ensure_type!/1` functions
  and their non raising `new_ok/1` and `ensure_type_ok/1` versions
  automatically defined. These functions have specs with field types defined.
  Use these functions to create a new instance and update an existing one.

      %{id: 123556}
      |> Wonder.new()
      |> Wonder.struct!(name: "Eiffel tower")
      %Wonder{id: 123556, name: "Eiffel tower"}

  At the run-time, each function checks the values passed in against
  the fields types set in the `t()` type. In case of mismatch, the functions
  raise an `ArgumentError`.

  #### Define a tag to enrich the field's type

  To define a tag define a module given the tag name and its type as a tuple
  of module name and associated value.

      use Domo.TaggedTuple
      defmodule Height do
        @type t :: {__MODULE__, __MODULE__.Meters.t() | __MODULE__.Foots.t()}

        defmodule Meters, do: @type t :: {__MODULE__, float}
        defmodule Foots, do: @type t :: {__MODULE__, float}
      end

  Type `t()` of the tag is a [tagged tuple](https://erlang.org/doc/getting_started/seq_prog.html#tuples).
  It's possible to have a tag or a tag chain added to a value like the following:

      alias Height.{Meters, Foots}
      m = {Height, {Meters, 324.0}}
      f = {Height, {Foots, 1062.992}}

  The tag chain attached to the value is a series of nested tagged tuples where
  the value is in the core. It's possible to extract the value
  with pattern matching.

      {Height, {Meters, 324.0}} == m

      @spec to_string(Height.t()) :: String.t()
      def to_string({Height, {Meters, val}}), do: to_string(val) <> " m"
      def to_string({Height, {Foots, val}}), do: to_string(val) <> " ft"

  #### Combine struct and tags

  To refine different kinds of field values, use the tag's `t()` type like that:

      defmodule Wonder do
        use Domo

        @typedoc "A world wonder. Ancient or contemporary."
        @enforce_keys [:id, :height]
        defstruct [:id, name: "", :height]

        @type t :: %__MODULE__{id: integer, name: String.t(), height: Height.t()}
      end

  The tag can be aliased or defined inline. Use autogenerated functions
  to build or modify struct having types verification.

      use Domo.TaggedTuple
      alias Height.Meters

      Wonder.new(id: 145, name: "Eiffel tower", height: {Height, {Meters, 324.0}})
      %Wonder{height: {Height, {Height.Meters, 324.0}}, id: 145, name: "Eiffel tower"}

  ### Overrides

  It's still possible to modify a struct with `%{... | s }` map syntax and other
  standard functions directly skipping the verification. Please, use
  the `ensure_type/1` struct's function to validate the struct's data after
  such modifications.

  ### Options

  The following options can be passed with `use Domo, [...]`

    * `unexpected_type_error_as_warning` - if set to true, prints warning
      instead of raising an exception for field type mismatch
      in autogenerated functions `new!/1`, `put!/1`, and `merge!/1`.
      Default is false.

  The default value for `*_as_warning` options can be changed globally,
  to do so add a line like the following into the config.exs file:

      config :domo, :unexpected_type_error_as_warning, true

  ### Pipeland

  To add a tag or a tag chain to a value in a pipe use `tag/2` macro
  and to remove use `untag!/2` macro appropriately.

  For instance:

      use Domo.TaggedTuple
      alias Order.Id

      identifier
      |> untag!(Id)
      |> String.graphemes()
      |> Enum.intersperse("_")
      |> Enum.join()
      |> tag(Id)


  ## Limitations

  The recursive types like `@type t :: :end | {integer, t}` are not supported.

  We may not know your business problem; at the same time, the Domo library
  can help you to model the problem and understand it better.
  """

  alias Domo.TypeEnsurerFactory.ResolvePlanner
  alias Domo.MixProjectHelper
  alias Domo.Raises
  alias Mix.Tasks.Compile.Domo, as: DomoMixTask

  @doc false
  defmacro __using__(opts) do
    Raises.raise_use_domo_out_of_module!(__CALLER__)
    Raises.raise_absence_of_domo_compiler!(Mix.Project.config(), opts, __CALLER__)

    type_ensurer_module = Module.concat(__CALLER__.module, TypeEnsurer)

    implementation_to_be_generated_message = """
    The #{inspect(type_ensurer_module)} module implementation should be generated by Domo. \
    Please, ensure that :domo compiler is included after the :elixir \
    in the compilers list in the project's configuration mix.exs file.
    """

    quote do
      Module.register_attribute(__MODULE__, :domo_options, accumulate: false)
      Module.put_attribute(__MODULE__, :domo_options, unquote(opts))

      defmodule TypeEnsurer do
        @moduledoc false
        def ensure_type!(_structure) do
          raise unquote(implementation_to_be_generated_message)
        end
      end

      use Domo.TaggedTuple

      def new(enumerable \\ []) do
        struct = struct!(__MODULE__, enumerable)

        errors =
          Enum.reduce(Map.from_struct(struct), [], fn key_value, errors ->
            case TypeEnsurer.ensure_type!(key_value) do
              {:error, _} = error ->
                [TypeEnsurer.pretty_error(error) | errors]

              _ ->
                errors
            end
          end)

        unless Enum.empty?(errors) do
          __raise_or_warn(ArgumentError, """
          the following values mismatch expected types of fields of \
          struct #{inspect(__MODULE__)}:

          #{Enum.join(errors, "\n\n")}\
          """)
        end

        struct
      end

      defp __raise_or_warn(error, message) do
        global_as_warning? = Application.get_env(:domo, :unexpected_type_error_as_warning, false)
        warn? = Keyword.get(unquote(opts), :unexpected_type_error_as_warning, global_as_warning?)

        if warn? do
          IO.warn(message)
        else
          raise error, message
        end
      end

      def new_ok(enumerable \\ []) do
        struct = struct(__MODULE__, enumerable)

        errors =
          Enum.reduce(Map.from_struct(struct), [], fn key_value, errors ->
            case TypeEnsurer.ensure_type!(key_value) do
              {:error, _} = error ->
                [TypeEnsurer.pretty_error_by_key(error) | errors]

              _ ->
                errors
            end
          end)

        if Enum.empty?(errors) do
          {:ok, struct}
        else
          {:error, errors}
        end
      end

      def ensure_type!(struct) do
        %name{} = struct

        unless name == __MODULE__ do
          raise ArgumentError, """
          the #{inspect(__MODULE__)} structure should be passed as \
          the first argument value instead of #{inspect(name)}.\
          """
        end

        errors =
          Enum.reduce(Map.from_struct(struct), [], fn key_value, errors ->
            case TypeEnsurer.ensure_type!(key_value) do
              {:error, _} = error ->
                [TypeEnsurer.pretty_error(error) | errors]

              _ ->
                errors
            end
          end)

        unless Enum.empty?(errors) do
          __raise_or_warn(ArgumentError, """
          the following values mismatch expected types of fields of \
          struct #{inspect(__MODULE__)}:

          #{Enum.join(errors, "\n\n")}\
          """)
        end

        struct
      end

      def ensure_type_ok(struct) do
        %name{} = struct

        unless name == __MODULE__ do
          raise ArgumentError, """
          the #{inspect(__MODULE__)} structure should be passed as \
          the first argument value instead of #{inspect(name)}.\
          """
        end

        errors =
          Enum.reduce(Map.from_struct(struct), [], fn key_value, errors ->
            case TypeEnsurer.ensure_type!(key_value) do
              {:error, _} = error ->
                [TypeEnsurer.pretty_error_by_key(error) | errors]

              _ ->
                errors
            end
          end)

        if Enum.empty?(errors) do
          :ok
        else
          {:error, errors}
        end
      end

      @before_compile {Domo, :struct_function_specs}

      @before_compile {Raises, :raise_not_in_a_struct_module!}
      @before_compile {Raises, :raise_no_type_t_defined!}

      @after_compile {Domo, :collect_types_for_domo_compiler}
    end
  end

  @doc false
  def collect_types_for_domo_compiler(env, bytecode) do
    project = MixProjectHelper.global_stub() || Mix.Project
    plan_path = DomoMixTask.manifest_path(project, :plan)

    {:ok, _pid} = ResolvePlanner.ensure_started(plan_path)
    :ok = ResolvePlanner.keep_module_environment(plan_path, env.module, env)

    {:"::", _, [{:t, _, _}, {:%, _, [_module_name, {:%{}, _, field_type_list}]}]} =
      bytecode
      |> Code.Typespec.fetch_types()
      |> elem(1)
      |> Enum.find_value(fn {:type, {:t, _, _} = t} -> t end)
      |> Code.Typespec.type_to_quoted()

    unless is_nil(field_type_list) do
      Enum.each(field_type_list, fn {field, quoted_type} ->
        :ok ==
          ResolvePlanner.plan_types_resolving(plan_path, env.module, field, quoted_type)
      end)
    end

    :ok == ResolvePlanner.flush(plan_path)
  end

  @doc false
  defmacro struct_function_specs(env) do
    add_spec? =
      env.module
      |> Module.get_attribute(:domo_options)
      |> Keyword.get(:no_specs, false) == false

    if add_spec? do
      quote do
        @spec new(Enum.t()) :: t()
        @spec new_ok(Enum.t()) :: t()
        @spec ensure_type!(t()) :: t()
        @spec ensure_type_ok(t()) :: {:ok, t()} | {:error, term}
      end
    end
  end
end
