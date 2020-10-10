defmodule Domo do
  @moduledoc """
  Domo is a library to model a business domain with type-safe structs and
  composable tagged tuples.

  It's a library to define what piece of data is what and make a dialyzer
  and run-time type verification to cover one's back, reminding about taken
  definitions.

  The library aims for two goals:

    * to allow a business domain entity's valid states with a struct of fields
      of generic and tagged types

    * to automatically verify that the construction of the entity's struct
      leads to one of the allowed valid states only

  The validation of the incoming data is on the author of the concrete
  application. The library can only ensure the consistent assembly
  of that valid data into structs according to given definitions throughout
  the app.

  ## Rationale

  The struct is one of the foundations of domain models in Elixir. One common
  way to validate that input data is of the model's type is to do it within
  a constructor function like the following:

      defmodule User do
        type t :: %__MODULE__{id: integer, name: String.t()}

        defstruct [:id, :name]

        def new(id: id, name: name) when is_integer(id) and is_binary(name),
          do: struct!(__MODULE__, id: id, name: name)
      end

  The code written above repeats for almost every entity in the application.
  And it'd be great to make it generated automatically reducing the structure
  definition to the minimal preferably declarative style.

  One way to do this is with the Domo library like that:

      defmodule User do
        use Domo

        typedstruct do
          field :id, integer
          field :name, String.t()
          field :post_address, :not_given | String.t(), default: :not_given
        end
      end

  Thanks to the declarative syntax from the [TypedStruct](https://hexdocs.pm/typed_struct/),
  the type and struct definitions are in the module. What's the Domo library
  adds on top is the set of `new/1` `put/1` and `merge/1` functions and their
  raising versions `new!/1`, `put!/1`, and `merge!/1`. These functions verify
  that arguments are of the field types and then build or modify the struct
  otherwise returning an error or raising the `ArgumentError` exception.

  The construction with automatic verification of the User struct can
  be as immediate as that:

      User.new!(id: 1, name: "John")
      %User{id: 1, name: "John", post_address: :not_given}

      User.new!(id: 2, name: nil, post_address: 3)
      ** (ArgumentError) Can't construct %User{...} with new!([id: 2, name: nil, post_address: 3])
          Unexpected value type for the field :name. The value nil doesn't match the String.t() type.
          Unexpected value type for the field :post_address. The value 3 doesn't match the :not_given | String.t() type.

  To modify an existing struct the put of merge functions can be used like that:

      User.put!(user, :name, "John Bongiovi")
      %User{id: 1, name: "John Bongiovi", post_address: :not_given}

      User.merge!(user, %{name: "John Francis Bongiovi", post_address: :not_given, genre: :rock, albums: 20})
      %User{id: 1, name: "John Francis Bongiovi", post_address: :not_given}

  The merge!/2 function verifies fields that belong to struct ignoring others.
  All generated functions accept any enumerable with field key-value pairs
  like maps or keyword lists.

  ### Further refinement with tags

  So far, so good. Let's say that we have another entity in our
  system - the Order that has an identifier as well. Both ids for User
  and Order structs are of the integer type. How to ensure that we don't mix
  them up throughout the various execution paths in the application?
  One way to do that is to attach an appropriate tag to each of the ids
  with [tagged tuple](https://erlang.org/doc/getting_started/seq_prog.html#tuples) like the following:

      defmodule User do
        use Domo

        defmodule Id do end

        typedstruct do
          field :id, {Id, integer}
          field :name, String.t()
          field :post_address, :none | String.t(), default: :none
        end
      end

      defmodule Order do
        use Domo

        defmodule Id do end

        typedstruct do
          field :id, {Id, integer}
          field :name, String.t()
        end
      end

      User.new!(id: {User.Id, 152}, name: "Bob")
      %User{id: {User.Id, 152}, name: "Bob"}

      User.new!(id: {Order.Id, 153}, name: "Fruits")
      ** (ArgumentError) Can't construct %User{...} with new!([id: {Order.Id, 153}, name: "Fruits"])
          Unexpected value type for the field :id. The value {Order.Id, 153} doesn't match the {User.Id, integer} type.

  The additional tuples here and there seem cumbersome. One way to make
  the tag definition elegant is with `deftag/2` macro.
  We can rewrite the code to more compact way like this:

      defmodule User do
        use Domo

        deftag Id, for_type: integer

        typedstruct do
          field :id, Id.t()
          field :name, String.t()
          field :post_address, :none | String.t(), default: :none
        end
      end

      defmodule Order do
        use Domo

        deftag Id, for_type: integer

        typedstruct do
          field :id, Id.t()
          field :name, String.t()
        end
      end

      import Domo
      User.new!(id: {User.Id, 152}, name: "Bob")
      %User{id: {User.Id, 152}, name: "Bob", post_address: :none}

      Order.new!(id: {Order.Id, 153}, name: "Fruits")
      %Order{id: {Order.Id, 153}, name: "Fruits"}

  In the example above the `deftag/2` macro defines the tag - Id module and
  the type t :: {Id, integer} in it.

  ### Third dimension for structures with tag chains 🍿

  Let's say one of the business requirements is to register the quantity
  of the Order in kilograms or units. That means that the structure's quantity
  field value can be float or integer. It'd be great to keep the kind
  of quantity alongside the value for the sake of local reasoning in different
  parts of the application. One possible way to do that is to use tag chains
  like that:

      defmodule Order do
        use Domo

        deftag Id, for_type: integer

        deftag Quantity do
          for_type __MODULE__.Kilograms.t() | __MODULE__.Units.t()

          deftag Kilograms, for_type: float
          deftag Units, for_type: integer
        end

        typedstruct do
          field :id, Id.t()
          field :name, String.t()
          field :quantity, Quantity.t()
        end
      end

      import Domo
      alias Order.{Id, Quantity}
      alias Order.Quantity.{Kilograms, Units}

      Order.new!(id: {Id, 158}, name: "Fruits", quantity: {Quantity, {Kilograms, 12.5}})
      %Order{
        id: {Order.Id, 158},
        name: "Fruits",
        quantity: {Order.Quantity, {Order.Quantity.Kilograms, 12.5}}
      }

      Order.new!(id: {Id, 159}, name: "Bananas", quantity: {Quantity, "5 boxes"})
      ** (ArgumentError) Can't construct %Order{...} with new!([id: {Order.Id, 159}, name: "Bananas", quantity: {Order.Quantity, "5 boxes"}])
          Unexpected value type for the field :quantity. The value {Order.Quantity, "5 boxes"} doesn't match the Quantity.t() type.

      def to_string(%Order{quantity: {Quantity, {Kilograms, kilos}}}), do: to_string(kilos) <> "kg"
      def to_string(%Order{quantity: {Quantity, {Units, kilos}}}), do: to_string(kilos) <> " units"

  In the example above the construction with invalid quantity raises
  the exception. And if there is no `to_string` function for one of the quantity
  kinds defined the no function clause matching error raises in run-time.

  That's how possible to define valid states for `Order` with `typedstruct/1`
  and `deftag/2` macro and keep the structs consistent throughout the app
  with type verifications in autogenerated `new/1`, `put/1`, and `merge/1` functions.

  ## Usage

  ### Setup

  To use Domo in your project, add this to your Mix dependencies:

      {:domo, "~> #{Mix.Project.config()[:version]}"}

  To avoid `mix format` putting extra parentheses around macro calls,
  you can add to your `.formatter.exs`:

      [
        ...,
        import_deps: [:domo]
      ]

  ### General usage

  #### Define a structure

  To describe a structure with field value contracts, use Domo, then define
  your struct with a `typedstruct/1` block.

      defmodule Wonder do
        use Domo

        @typedoc "A world wonder. Ancient or contemporary."
        typedstruct do
          field :id, integer
          field :name, String.t(), default: ""
        end
      end

  Define each field with `field/3` macro. The generated structure has all fields
  enforced, default values if specified for fields, and type `t()` constructed
  from field types. See TypedStruct library documentation for implementation
  details.

  Same time the generated structure has `new/1`, `merge/2`, and `put/3` functions
  or their raising versions automatically defined. These functions have specs
  with field types defined. Use these functions to create a new instance
  and update an existing one.

      %{id: 123556}
      |> Wonder.new!()
      |> Wonder.put!(:name, "Eiffel tower")
      %Wonder{id: 123556, name: "Eiffel tower"}

  At the compile-time, the dialyzer can do static analysis of functions
  contract.
  At the run-time, each function checks the values passed in against
  the types set in the `field/3` macro. In case of mismatch, the functions
  raise an `ArgumentError`.

  #### Define a tag to enrich the field's type

  To define a tag on the top level of a file import Domo, then give
  the tag name and type associated value with `deftag/2` macro.

      import Domo
      deftag Height do
        for_type __MODULE__.Meters.t() | __MODULE__.Foots.t()

        deftag Meters, for_type: float
        deftag Foots, for_type: float
      end

  Any tag is a module by itself. Type `t()` of the tag is a [tagged tuple](https://erlang.org/doc/getting_started/seq_prog.html#tuples).
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

        alias Height

        @typedoc "A world wonder. Ancient or contemporary."
        typedstruct do
          field :id, integer
          field :name, String.t(), default: ""
          field :height, Height.t()
        end
      end

  The tag can be aliased or defined inline. Use autogenerated functions
  to build or modify struct having types verification.

      import Domo
      alias Height.Meters

      Wonder.new!(id: 145, name: "Eiffel tower", height: {Height, {Meters, 324.0}})
      %Wonder{height: {Height, {Height.Meters, 324.0}}, id: 145, name: "Eiffel tower"}

  ### Overrides

  To make custom validations of the data override the appropriate `new/1` `put/1`,
  `merge/1` function or their raising version. Please, be careful and modify
  struct with a `super(...)` call. This call should be the last in the overridden
  function.

  It's still possible to modify a struct with `%{... | s }` map syntax and other
  standard functions directly skipping the verification. Please, use
  the autogenerated structs functions mentioned above for the type-safety
  and data consistency.

  ### Options

  After the module compilation, the Domo library checks if all tags attached
  with `tag/2` have proper aliases at the call sites. If it can't find a tag's
  module, it raises the `CompileError` exception.

  The following options can be passed with `use Domo, [...]`

    * `undefined_tag_error_as_warning` - if set to true, prints warning
      instead of raising an exception for undefined tags. Default is false.

    * `unexpected_type_error_as_warning` - if set to true, prints warning
      instead of raising an exception for field type mismatch
      in autogenerated functions `new!/1`, `put!/1`, and `merge!/1`.
      Default is false.

    * `no_field` - if set to true, skips import of `typedstruct/1`
      and `field/3` macros, useful with the import of the `Ecto.Schema`
      in the same module. Default is false.

  The default value for `*_as_warning` options can be changed globally,
  to do so add a line like the following into the config.exs file:

      config :domo, :unexpected_type_error_as_warning, true

  ### Reflexion

  Each struct or tag defines `__tags__/0` function that returns
  a list of tags defined in the module.
  Additionally each tag module defines `__tag__?/0` function that returns
  `true`.

  For example:

      iex.(1)> defmodule Order do
      ....(1)>   use Domo
      ....(1)>
      ....(1)>   deftag Id, for_type: String.t()
      ....(1)>
      ....(1)>   deftag Quantity do
      ....(1)>      for_type __MODULE__.Kilograms.t() | __MODULE__.Units.t()
      ....(1)>
      ....(1)>      deftag Kilograms, for_type: float
      ....(1)>      deftag Units, for_type: integer
      ....(1)>   end
      ....(1)>
      ....(1)>   deftag Note, for_type: :none | String.t()
      ....(1)>
      ....(1)>   typedstruct do
      ....(1)>     field :id, Id.t()
      ....(1)>     field :quantity, Quantity.t()
      ....(1)>     field :note, Note.t(), default: {Note, :none}
      ....(1)>   end
      ....(1)> end
      {:module, Order,
      <<70, 79, 82, 49, 0, 0, 17, 156, 66, 69, 65, 77, 65, 116, 85, 56, 0, 0, 1, 131,
        0, 0, 0, 41, 12, 69, 108, 105, 120, 105, 114, 46, 79, 114, 100, 101, 114, 8,
        95, 95, 105, 110, 102, 111, 95, 95, 7, ...>>, :ok}

      iex.(2)> Order.__tags__
      [Order.Id, Order.Quantity, Order.Note]

      iex.(3)> Order.Id.__tag__?
      true

  ### Pipeland

  To add a tag or a tag chain to a value in a pipe use `tag/2` macro
  and to remove use `untag!/2` macro appropriately.

  For instance:

      import Domo
      alias Order.Id

      identifier
      |> untag!(Id)
      |> String.graphemes()
      |> Enum.intersperse("_")
      |> Enum.join()
      |> tag(Id)


  ## Limitations

  When one uses a remote type for the field of a struct, the runtime type check
  will work properly only if the remote type's module is compiled into
  the .beam file on the disk, which means, that modules generated in memory
  are not supported. That's because of the way the Erlang functions load types.

  We may not know your business problem; at the same time, the Domo library
  can help you to model the problem and understand it better.
  """
  @doc false
  defmacro __using__(opts) do
    if false == module_context?(__CALLER__) do
      raise(CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description: "use Domo should be called in a module scope only. Try import Domo instead."
      )
    else
      imports = [
        deftag: 2,
        for_type: 1,
        untag!: 2
      ]

      imports =
        imports ++
          if Keyword.get(opts, :no_field) do
            []
          else
            [typedstruct: 1, field: 2, field: 3]
          end ++
          if Keyword.get(opts, :no_tag) do
            []
          else
            [tag: 2]
          end

      quote do
        Module.register_attribute(__MODULE__, :domo_tags, accumulate: true)
        Module.register_attribute(__MODULE__, :domo_defined_tag_names, accumulate: true)

        Module.register_attribute(__MODULE__, :domo_options, accumulate: false)
        Module.put_attribute(__MODULE__, :domo_options, unquote(opts))

        @before_compile Domo
        @after_compile {Domo.CompilationChecks, :warn_and_raise_undefined_tags}

        import Domo, only: unquote(imports)
      end
    end
  end

  @doc false
  defp module_context?(env), do: not is_nil(env.module) and is_nil(env.function)

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      def __tags__, do: Enum.reverse(@domo_defined_tag_names)
    end
  end

  @doc """
  Defines a tag for a type.

  The macro generates a module with a given name that is an atom
  and can be used as a tag in a tagged tuple.

  The generated module defines a `@type t()`, a tagged tuple where the first
  element is a module's name, and the second element is a type of the value.

  It can be called in one-line and block forms.

  ## Examples

      # Define a tag as a submodule named ExperienceYears
      # Colleague.ExperienceYears.t() is {Colleague.ExperienceYears, integer}
      iex> defmodule Colleague do
      ...>   import Domo
      ...>
      ...>   deftag ExperienceYears, for_type: integer
      ...>
      ...>   @type seniority() :: ExperienceYears.t()
      ...> end

  In the block form, you can specify the `for_type/1` macro.
  The macro is required and should be passed within the do: block.
  It's possible to add other tags into the current one.

  ## Examples

      iex> import Domo
      ...> deftag Email do
      ...>   for_type :none | __MODULE__.Unverified.t() | __MODULE__.Verified.t()
      ...>
      ...>   deftag Unverified, for_type: String.t()
      ...>   deftag Verified, for_type: String.t()
      ...> end

      ...> alias Email.Unverified
      ...> {Email, {Unverified, "some@server.com"}}
      {Email, {Email.Unverified, "some@server.com"}}


  """
  defmacro deftag(name, for_type: type) do
    quote do
      Domo.deftag unquote(name) do
        Domo.for_type(unquote(type))
      end
    end
  end

  defmacro deftag(name, do: block) do
    put_name_attr = if module_context?(__CALLER__), do: quote_put_expanded_tag_name_to_attr(name)

    quote do
      unquote(put_name_attr)

      defmodule unquote(name) do
        Module.register_attribute(__MODULE__, :domo_defined_tag_names, accumulate: true)
        @before_compile Domo

        unquote(block)

        def __tag__?, do: true
      end
    end
  end

  @doc false
  defp quote_put_expanded_tag_name_to_attr(name) do
    quote do
      Module.put_attribute(__MODULE__, :domo_defined_tag_names, __MODULE__.unquote(name))
    end
  end

  @doc """
  Defines a tagged tuple type `t()`.

  ## Example

      deftag Title do
        # Define a tagged tuple type spec @type t :: {__MODULE__, String.t()}
        for_type String.t()
      end

  """
  defmacro for_type(type) do
    quote do
      @type t :: {__MODULE__, unquote(type)}
      @type value_t :: unquote(type)
    end
  end

  @doc """
  Defines a struct with all keys enforced, a `new/1`, `merge/2`, `put/2`,
  and their bang versions.

  The macro defines a struct by passing an `[enforced: true]` option,
  and the `do` block to the `typed_struct` function of the same-named library.
  It's possible to use plugins for the TypedStruct in place,
  see [library's documentation](https://hexdocs.pm/typed_struct) for syntax details.

  The default implementation of the `new!/1` constructor function looks like
  that:

      def new!(enumerable), do: ... struct!(__MODULE__, enumerable)

  The `merge!/2` function should be used to update several keys of the existing
  structure at once. The keys missing in the structure are ignored.

      def merge!(%__MODULE__{} = s, enumerable), do: ...

  The `put!/2` function should be used to update one key of the existing structure.

      def put!(%__MODULE__{} = s, field, value), do: ...

  Evenry function have a spec generated from the struct fields type spec.
  Meaning, that the dialyzer can indicate contract breaks when values with wrong
  types are used to construct or modify the structure.

  At the run-time each of the generated functions checks every argument
  with the type spec that is set for the field with `field/3` macro.
  And raises or returns an error on mismatch between the value type
  and the field's type.

  These functions can be overridden.

  ## Examples

      iex> defmodule Person do
      ...>   use Domo
      ...>
      ...>   @typedoc "A person"
      ...>   typedstruct do
      ...>     field :name, String.t()
      ...>   end
      ...> end

      ...> p = Person.new!(name: "Sarah Connor")
      %Person{name: "Sarah Connor"}

      ...> p = Person.put!(p, :name, "Connor")
      %Person{name: "Connor"}

      ...> {:error, _} = Person.merge(p, name: 9)
      {:error, {:value_err, "Unexpected value type for the field :name. The value 9 doesn't match the String.t() type."}}

  All defined fields in the struct are enforced automatically. To specify
  an optional field, one good practice is to do it with a distinct atom explicitly.

      iex> defmodule Hero do
      ...>   use Domo
      ...>
      ...>   @typedoc "A hero"
      ...>   typedstruct do
      ...>     field :name, String.t()
      ...>     field :optional_kid, :none | String.t(), default: :none
      ...>   end
      ...>
      ...>   def new!(name) when is_binary(name), do: super(name: name)
      ...>   def new!(args), do: super(args)
      ...> end

      ...> Hero.new!("Sarah Connor")
      %Hero{name: "Sarah Connor", optional_kid: :none}

      ...> Hero.new!(name: "Sarah Connor", optional_kid: "John Connor")
      %Hero{name: "Sarah Connor", optional_kid: "John Connor"}

      ...> Hero.new!()
      ** (ArgumentError) the following keys must also be given when building struct Hero: [:name]

      ...> Hero.new!(name: "Sarah Connor", optional_kid: nil)
      ** (ArgumentError) Can't construct %Hero{...} with new!([name: "Sarah Connor", optional_kid: nil])
          Unexpected value type for the field :optional_kid. The value nil doesn't match the :none | String.t() type.

  """
  defmacro typedstruct(do: block) do
    Module.register_attribute(__CALLER__.module, :domo_struct_key_type, accumulate: true)

    # :domo_struct_key_type is accumulated during the following expansion
    block = expand_in_block_once(block, __CALLER__)

    fields_kw_spec =
      Enum.reverse(List.wrap(Module.get_attribute(__CALLER__.module, :domo_struct_key_type)))

    alias Domo.StructFunctionsGenerator
    alias Domo.TypeCheckerGenerator

    quote location: :keep do
      unquote(TypeCheckerGenerator.module(fields_kw_spec, __CALLER__))

      require TypedStruct

      TypedStruct.typedstruct([enforce: true], do: unquote(block))

      unquote(StructFunctionsGenerator.quoted_new_funs(fields_kw_spec, __CALLER__.module))
      unquote(StructFunctionsGenerator.quoted_put_funs(fields_kw_spec))
      unquote(StructFunctionsGenerator.quoted_merge_funs(fields_kw_spec))
    end
  end

  defp expand_in_block_once({:__block__, meta, fields}, env) do
    {:__block__, meta, Enum.map(fields, &Macro.expand_once(&1, env))}
  end

  defp expand_in_block_once(field, env) do
    Macro.expand_once(field, env)
  end

  @doc """
  Defines a field in a typed struct.

  ## Example

      # A field named :example of type String.t()
      field :example, String.t()
      field :title, String.t(), default: "Hello world!"

  ## Options

    * `default` - sets the default value for the field
  """
  defmacro field(name, type, [default: _] = opts) do
    Module.put_attribute(__CALLER__.module, :domo_struct_key_type, {name, type})

    quote do
      TypedStruct.field(unquote(name), unquote(type), unquote(opts))
    end
  end

  defmacro field(name, type) do
    Module.put_attribute(__CALLER__.module, :domo_struct_key_type, {name, type})

    quote do
      TypedStruct.field(unquote(name), unquote(type))
    end
  end

  @doc """
  Returns a tagged tuple by joining the tag chain with the value.

  The macro supports up to 6 links in the tag chain.

  ## Example

      iex> import Domo
      ...> tag(2.5, SomeTag)
      {SomeTag, 2.5}

      iex> import Domo
      ...> tag(7, {A, {Tag, Chain}})
      {A, {Tag, {Chain, 7}}}
  """
  defmacro tag(value, tag_chain) do
    m = Macro.expand_once(tag_chain, __CALLER__)

    do_tag_q =
      quote do
        Domo.do_tag(unquote(value), unquote(tag_chain))
      end

    case {is_atom(m), module_atom?(m)} do
      {true, false} ->
        quote do
          raise(
            ArgumentError,
            "Second argument of tag\/2 function is #{inspect(unquote(m))}. Expected a tag defined with deftag/2."
          )
        end

      {true, true} ->
        if not is_nil(__CALLER__.module) do
          st_entry = List.first(Macro.Env.stacktrace(__CALLER__))
          Module.put_attribute(__CALLER__.module, :domo_tags, {m, st_entry})
        end

        do_tag_q

      {false, _} ->
        do_tag_q
    end
  end

  @doc false
  defp module_atom?(a) when not is_atom(a), do: false

  defp module_atom?(a) do
    f = String.first(Atom.to_string(a))
    f == String.upcase(f)
  end

  @doc false
  def do_tag(v, t1) when is_atom(t1), do: {t1, v}
  def do_tag(v, {t2, t1}) when is_atom(t2) and is_atom(t1), do: {t2, {t1, v}}

  def do_tag(v, {t3, {t2, t1}})
      when is_atom(t3) and is_atom(t2) and is_atom(t1),
      do: {t3, {t2, {t1, v}}}

  def do_tag(v, {t4, {t3, {t2, t1}}})
      when is_atom(t4) and is_atom(t3) and is_atom(t2) and is_atom(t1),
      do: {t4, {t3, {t2, {t1, v}}}}

  def do_tag(v, {t5, {t4, {t3, {t2, t1}}}})
      when is_atom(t5) and is_atom(t4) and is_atom(t3) and is_atom(t2) and is_atom(t1),
      do: {t5, {t4, {t3, {t2, {t1, v}}}}}

  def do_tag(v, {t6, {t5, {t4, {t3, {t2, t1}}}}})
      when is_atom(t6) and is_atom(t5) and is_atom(t4) and is_atom(t3) and is_atom(t2) and
             is_atom(t1),
      do: {t6, {t5, {t4, {t3, {t2, {t1, v}}}}}}

  @doc """
  Returns the value from the tagged tuple when the tag chain matches.

  Raises `ArgumentError` exception if the passed tag chain is not one that
  is in the tagged tuple. Supports up to 6 links in the tag chain.

  ## Examples

      iex> import Domo
      ...> value = {A, {Tag, {Chain, 2}}}
      ...> untag!(value, {A, {Tag, Chain}})
      2

      iex> import Domo
      ...> value = {Other, {Stuff, 2}}
      ...> untag!(value, {A, {Tag, Chain}})
      ** (ArgumentError) Tag chain {A, {Tag, Chain}} doesn't match one in the tagged tuple {Other, {Stuff, 2}}.

  """
  defmacro untag!(tagged_tuple, tag_chain) do
    m = Macro.expand_once(tag_chain, __CALLER__)

    do_untag_q =
      quote do
        Domo.do_untag!(unquote(tagged_tuple), unquote(tag_chain))
      end

    case {is_atom(m), module_atom?(m)} do
      {true, false} ->
        quote do
          raise(
            ArgumentError,
            "Second argument of untag!\/2 function is #{inspect(unquote(m))}. Expected a tag defined with deftag/2."
          )
        end

      {true, true} ->
        if not is_nil(__CALLER__.module) do
          st_entry = List.first(Macro.Env.stacktrace(__CALLER__))
          Module.put_attribute(__CALLER__.module, :domo_tags, {m, st_entry})
        end

        do_untag_q

      {false, _} ->
        do_untag_q
    end
  end

  @doc false
  def do_untag!({t1, v}, t1) when is_atom(t1), do: v
  def do_untag!({t2, {t1, v}}, {t2, t1}) when is_atom(t2) and is_atom(t1), do: v

  def do_untag!({t3, {t2, {t1, v}}}, {t3, {t2, t1}})
      when is_atom(t3) and is_atom(t2) and is_atom(t1),
      do: v

  def do_untag!({t4, {t3, {t2, {t1, v}}}}, {t4, {t3, {t2, t1}}})
      when is_atom(t4) and is_atom(t3) and is_atom(t2) and is_atom(t1),
      do: v

  def do_untag!({t5, {t4, {t3, {t2, {t1, v}}}}}, {t5, {t4, {t3, {t2, t1}}}})
      when is_atom(t5) and is_atom(t4) and is_atom(t3) and is_atom(t2) and is_atom(t1),
      do: v

  def do_untag!({t6, {t5, {t4, {t3, {t2, {t1, v}}}}}}, {t6, {t5, {t4, {t3, {t2, t1}}}}})
      when is_atom(t6) and is_atom(t5) and is_atom(t4) and is_atom(t3) and is_atom(t2) and
             is_atom(t1),
      do: v

  def do_untag!(tt, c),
    do:
      Kernel.raise(
        ArgumentError,
        "Tag chain #{inspect(c)} doesn't match one in the tagged tuple #{inspect(tt)}."
      )
end
