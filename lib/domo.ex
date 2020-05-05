defmodule Domo do
  @moduledoc """
  **⚠️ Preview, requires Elixir 1.11.0-dev to run**

  Domo is a library for defining custom composable types for fields of a struct
  to make these pieces of data to flow through the app consistently.

  The library aims for two goals:

    * to model a business domain entity's possible valid states with custom
      types for fields of struct representing the entity
    * to verify that entity structs are assembled to one of the allowed
      valid states at compile-time

  It's a library to define what piece of data is what and make
  a compiler and dialyzer to cover one's back, reminding about taken
  definitions.

  The validation of the incoming data is on the author of the concrete
  application. The library can only ensure the consistent processing
  of that valid data throughout the system.

  The library has the means to build structs and depends on the [TypedStruct](https://hexdocs.pm/typed_struct/)
  to do so.

  ## Rationale

  To model a business domain entity, one may define a named struct with several
  fields of primitive data types. Construction of the struct from parsed data
  can look like this:

      %Order{
        id: "156",
        quantity: 2.5
        note: "Deliver on Tue"
      }

  and modification of the struct's data can be done with a function of
  the following signature:

      @spec put_quantity(Order.t(), float()) :: Order.t()
      def put_quantity(order, quantity) ...

  Primitive types of `binary` and `float` are universal and have no relation
  to the `Order` struct specifically. That is, any data of these types
  can leak into the new struct instance by mistake.
  The `float` type defining quantity reflects no measure from the business
  domain. Meaning, that a new requirement - to measure quantity in Kilograms
  or Units makes space for misinterpretation of the quantity field's value
  processed in any part of the app.

  ### How about some domain modeling?

  In the context given above, it'd be great to define a contract to allow
  only valid states for Order struct fields, that enables:

    * local reasoning about the relation of value to the struct in any nested
      function of the app
    * compile-time verification of assembling/updating of the structure
      from values that relates only to it

  One possible valid way to do this is to use Domo library like the following:

      defmodule Order do
        use Domo

        deftag Id, for_type: String.t()

        deftag Quantity do
           for_type __MODULE__.Kilograms.t() | __MODULE__.Units.t()

           deftag Kilograms, for_type: float
           deftag Units, for_type: integer
        end

        deftag Note, for_type: :none | String.t()

        typedstruct do
          field :id, Id.t()
          field :quantity, Quantity.t()
          field :note, Note.t(), default: Note --- :none
        end
      end

  Then the construction of the struct becomes like this:

      Order.new!(%{
        id: Id --- "156",
        quantity: Quantity --- Kilograms --- 2.5
        note: Note --- "Deliver on Tue"
      })

  And a signature of a custom function to modify the struct becomes like this:

      @spec put_quantity(Order.t(), Order.Quantity.t()) :: Order.t()
      def put_quantity(order, Quantity --- Units --- units) ...
      def put_quantity(order, Quantity --- Kilograms --- kilos) ...

  Thanks to the Domo library, every field of the structure becomes a [tagged tuple](https://erlang.org/doc/getting_started/seq_prog.html#tuples)
  consisting of a tag and a value. A tag is a module itself.
  Several tags can be nested, defining valid tag chains as a shape for values
  of primitive type. That makes it possible to do pattern matching against
  the shape of the struct's value. That enables the dialyzer to validate
  contracts for the structure itself and the structure's field values.

  ## Usage

  ### Setup

  To use Domo in your project, add this to your Mix dependencies:

      {:domo, "~> #{Mix.Project.config()[:version]}"}

  To avoid `mix format` putting parentheses on tagged tuples definitions
  made with `---/2` operator, you can add to your `.formatter.exs`:

      [
        ...,
        import_deps: [:typed_struct]
      ]

  ### General usage

  #### Define a tag

  To define a tag on the top level of a file import `Domo`, then define the
  tag name and type associated value with `deftag/2` macro.

      import Domo

      deftag Title, for_type: String.t()
      deftag Height do
        for_type: __MODULE__.Meters.t() | __MODULE__.Foots.t()

        deftag Meters, for_type: float
        deftag Foots, for_type: float
      end

  Any tag is a module by itself. Type `t()` of the tag is a tagged tuple.
  When defining a tag in a block form, you can specify the associated value
  type through the `for_type/1` macro.

  To add a tag or a tag chain to a value use `---/2` macro.

      alias Height.{Meters, Foots}

      t = Title --- "Eiffel tower"
      m = Height --- Meters --- 324.0
      f = Height --- Foots --- 1062.992

  Under the hood, the tag chain is a series of nested tagged tuples where the
  value is in the core. Because of that, you can use the `---/2` macro
  in pattern matching.

      {Height, {Meters, 324.0}} == m

      @spec to_string(Height.t()) :: String.t()
      def to_string(Height --- Meters --- val), do: to_string(val) <> " m"
      def to_string(Height --- Foots --- val), do: to_string(val) <> " ft"

  Each tag module has type `t()` of tagged tuple with the name of tag itself
  and a value type specified with `for_type`. Use `t()` in the function spec to
  inform the dialyzer about the tagged argument.

  #### Define a structure

  To define a structure with field value's contracts, use `Domo`, then define
  your struct with a `typedstruct/1` block.

      defmodule Order do
        use Domo

        deftag Id, for_type: String.t()
        deftag Note, for_type: :none | String.t()

        @typedoc "An Order from Sales context"
        typedstruct do
          field :id, Id.t()
          field :note, Note.t(), default: Note --- :none
        end
      end

  Each field is defined through `field/3` macro. The generated structure has
  all fields enforced, default values specified by `default:` key,
  and type t() constructed with field types.
  See [TypedStruct library documentation](https://hexdocs.pm/typed_struct/)
  for implementation details.

  Use `new!/1` and `put!/3` functions that are automatically defined
  for the struct to create a new instance and update an existing one.

      alias Order
      alias Order.{Id, Note}

      %{id: Id --- "o123556"}
      |> Order.new!()
      |> Order.put!(:note, Note --- "Deliver on Tue")

  The dialyzer can check if properly tagged values are passed as parameters
  to these functions. The `new!/1` function can be overridden to make data
  validations.

  After the module compilation, the Domo library checks if all tags that
  are used with the `---/2` operator are defined and appropriately aliased.
  The following options can be passed with `use Domo, ...`

  #### Options

      * `undefined_tag_error_as_warning` - if set to true, prints warning
        instead of raising an exception for undefined tags.

      * `no_field` - if set to true, skips import of typedstruct/1
        and field/3 macros, useful with the import of the Ecto.Schema
        in the same module.

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
      ....(1)>     field :note, Note.t(), default: Note --- :none
      ....(1)>   end
      ....(1)> end
      {:module, Order,
      <<70, 79, 82, 49, 0, 0, 17, 156, 66, 69, 65, 77, 65, 116, 85, 56, 0, 0, 1, 131,
        0, 0, 0, 41, 12, 69, 108, 105, 120, 105, 114, 46, 79, 114, 100, 101, 114, 8,
        95, 95, 105, 110, 102, 111, 95, 95, 7, ...>>,
      [put!: 3, put!: 3, put!: 3, put!: 3, put!: 3]}
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

  Only a map is expected as the fields argument for the `new!/1` function
  because it's impossible to define a typespec for a keyword list with a
  set of required key-value pairs.

  It's still possible to construct a struct with a `new/1` function with
  fields of the wrong shape at runtime overlooking the dialyzer warnings.

  """
  @doc false
  defmacro __using__(opts) do
    if not module_context?(__CALLER__) do
      raise(CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description: "use Domo should be called in a module scope only. Try import Domo instead."
      )
    else
      imports = [
        deftag: 2,
        for_type: 1,
        ---: 2,
        tag: 2,
        untag!: 2
      ]

      imports =
        imports ++
          case Keyword.fetch(opts, :no_field) do
            {:ok, true} -> []
            _ -> [typedstruct: 1, field: 2, field: 3]
          end

      quote do
        Module.register_attribute(__MODULE__, :domo_tags, accumulate: true)
        Module.register_attribute(__MODULE__, :domo_defined_tag_names, accumulate: true)

        Module.register_attribute(__MODULE__, :domo_opts, accumulate: false)
        Module.put_attribute(__MODULE__, :domo_opts, unquote(opts))

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
      ...>   for_type :none | Unverified.t() | Verified.t()
      ...>
      ...>   deftag Unverified, for_type: String.t()
      ...>   deftag Verified, for_type: String.t()
      ...> end
      ...>
      ...> Email --- Email.Unverified --- "some@server.com"
      {DomoTest.Email, {DomoTest.Email.Unverified, "some@server.com"}}


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
  Defines a struct with all keys enforced, a `new!/1`, and a `put!/2` functions
  into it.

  The macro defines a struct by passing an `[enforced: true]` option,
  and the `do` block to the `typed_struct` function of the same-named library.
  See the [TypedStruct documentation](https://hexdocs.pm/typed_struct)
  for syntax details.

  The default implementation of the `new!/1` constructor function looks like
  the following:

      def new!(map), do: struct!(__MODULE__, map)

  The function can be overridden.

  The `put!/2` function should be used to update the existing structure.
  Its definition looks like the following:

      def put!(%__MODULE__{} = s, field, value)

  Both `new!/1` and `put!/2` have type specs defined from the struct fields.
  Meaning, that the dialyzer can indicate contract break when values with wrong
  tags are used to construct or modify the structure.

  Unfortunately, the dialyzer can't analyze wrongly typed values mixed
  with correctly typed in the keyword list. Because of that, the function
  taking a list of fields and values to be updated is impossible to define.

  ## Examples

      iex> defmodule Person do
      ...>   use Domo
      ...>
      ...>   @typedoc "A person"
      ...>   typedstruct do
      ...>     field :name, String.t()
      ...>   end
      ...> end
      ...>
      ...> p = Person.new!(%{name: "Sarah Connor"})
      ...> Person.put!(p, :name, "Connor")

  All defined fields are enforced automatically. We can specify an optional
  field with an atom and override `new!/1` to verify values before construction.

      iex> defmodule Hero do
      ...>   use Domo
      ...>
      ...>   @typedoc "A hero"
      ...>   typedstruct do
      ...>     field :name, String.t()
      ...>     field :optional_kid, :none | String.t(), default: :none
      ...>   end
      ...>
      ...>   def new!(name) when is_binary(name), do: super(%{name: name})
      ...>
      ...>   def new!(%{optional_kid: kid} = map) when kid in ["John Connor", :none],
      ...>     do: super(map)
      ...> end
      ...>
      ...> Hero.new!("Sarah Connor")
      ...> Hero.new!(%{name: "Sarah Connor", optional_kid: "John Connor"})

  """
  defmacro typedstruct(do: block) do
    Module.register_attribute(__CALLER__.module, :domo_struct_key_type, accumulate: true)

    block = expand_in_block_once(block, __CALLER__)

    fields_spec =
      Enum.reverse(List.wrap(Module.get_attribute(__CALLER__.module, :domo_struct_key_type)))

    put_defs = quoted_put_funs(fields_spec)

    quote do
      require TypedStruct
      TypedStruct.typedstruct([enforce: true], do: unquote(block))

      @spec new!(map :: %{unquote_splicing(fields_spec)}) :: __MODULE__.t()
      def new!(map), do: struct!(__MODULE__, map)

      defoverridable new!: 1

      unquote(put_defs)
    end
  end

  defp expand_in_block_once({:__block__, meta, fields}, env) do
    {:__block__, meta, Enum.map(fields, &Macro.expand_once(&1, env))}
  end

  defp expand_in_block_once(field, env) do
    Macro.expand_once(field, env)
  end

  defp quoted_put_funs(fields_spec) do
    fields_spec
    |> Enum.map(fn {key, type} -> quoted_put(key, type) end)
    |> List.insert_at(-1, quoted_put_raise_nonpresent_key())
    |> List.insert_at(-1, quoted_put_raise_struct_name())
  end

  defp quoted_put(key, type) do
    quote do
      @spec put!(s :: __MODULE__.t(), unquote(key), unquote(type)) :: __MODULE__.t()
      def put!(%__MODULE__{} = s, unquote(key), value), do: Map.replace!(s, unquote(key), value)
    end
  end

  defp quoted_put_raise_nonpresent_key do
    quote do
      def put!(%__MODULE__{} = s, key, val), do: Map.replace!(s, key, val)
    end
  end

  defp quoted_put_raise_struct_name do
    quote do
      def put!(%name{}, _key, _val),
        do:
          raise(
            ArgumentError,
            "#{inspect(__MODULE__)} structure was expected as the first argument and #{
              inspect(name)
            } was received."
          )
    end
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
  defmacro field(name, type) do
    Module.put_attribute(__CALLER__.module, :domo_struct_key_type, {name, type})

    quote do
      TypedStruct.field(unquote(name), unquote(type))
    end
  end

  defmacro field(name, type, [default: _] = opts) do
    Module.put_attribute(__CALLER__.module, :domo_struct_key_type, {name, type})

    quote do
      TypedStruct.field(unquote(name), unquote(type), unquote(opts))
    end
  end

  @doc """
  Defines a tagged tuple inline.

  The operator is right-associative. It adds a tag or a chain of tags to a value.

  ## Examples

      iex> import Domo
      ...> Tag --- 12
      {Tag, 12}

  """
  defmacro tag --- value do
    m = Macro.expand_once(tag, __CALLER__)

    if not module_atom?(m) do
      quote do
        raise(
          ArgumentError,
          "First argument of ---\/2 operator is #{inspect(unquote(m))}. Expected a tag defined with deftag/2."
        )
      end
    else
      if not is_nil(__CALLER__.module) do
        st_entry = List.first(Macro.Env.stacktrace(__CALLER__))

        Module.put_attribute(__CALLER__.module, :domo_tags, {m, st_entry})

        m = Macro.expand_once(value, __CALLER__)

        if module_atom?(m) do
          Module.put_attribute(__CALLER__.module, :domo_tags, {m, st_entry})
        end
      end

      quote do
        {unquote(tag), unquote(value)}
      end
    end
  end

  @doc false
  defp module_atom?(a) when not is_atom(a), do: false

  defp module_atom?(a) do
    f = String.first(Atom.to_string(a))
    f == String.upcase(f)
  end

  # Kernel.function_exported?(m, :tag?, 0)

  @doc """
  Returns tagged tuple by joining a tag chain with a value.

  The macro supports up to 6 links in the tag chain.

  ## Example

      iex> import Domo
      ...> tag(2.5, SomeTag)
      {SomeTag, 2.5}

      iex> import Domo
      ...> tag(7, A --- Tag --- Chain)
      {A, {Tag, {Chain, 7}}}
  """
  defmacro tag(v, t) do
    m = Macro.expand_once(t, __CALLER__)

    do_tag_q =
      quote do
        Domo.do_tag(unquote(v), unquote(t))
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
  Returns a value from a tagged tuple when a tag chain matches.

  Raises `ArgumentError` exception if the passed tag chain is not one that
  is in the tagged tuple.  Supports up to 6 links in the tag chain.

  ## Examples

      iex> import Domo
      ...> value = A --- Tag --- Chain --- 2
      ...> untag!(value, A --- Tag --- Chain)
      2

      # When the value is a tagged tuple with the different tag, we get an ArgumentError exception
      value = Other --- Stuff --- 2
      untag!(value, A --- Tag --- Chain)
      # ArgumentError, Tag chain {A, {Tag, Chain}} doesn't match one in the tagged tuple {Other, {Stuff, 2}}.

  """
  defmacro untag!(tuple, t) do
    m = Macro.expand_once(t, __CALLER__)

    do_untag_q =
      quote do
        Domo.do_untag!(unquote(tuple), unquote(t))
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
