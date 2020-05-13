defmodule Domo do
  @moduledoc """
  **⚠️ Preview, requires Elixir 1.11.0-dev to run**

  Domo is a library to model a business domain with composable tags
  and type-safe structs.

  It's a library to define what piece of data is what and make
  a dialyzer and run-time type checks to cover one's back,
  reminding about taken definitions.

  The library aims for two goals:

    * to model a business domain entity's possible valid states with custom
      types for fields of the struct representing the entity
    * to verify that entity structs are assembled to one of the allowed
      valid states in run-time

  The validation of the incoming data is on the author of the concrete
  application. The library can only ensure the consistent processing
  of that valid data according to type specs and definitions throughout
  the system.

  The library has the means to build structs and relies on the [TypedStruct](https://hexdocs.pm/typed_struct/)
  to do so. It's possible to extend and configure many of the TypedStruct
  features transparently.

  If you practice Domain Driven Design, this library can be used to
  model entities, value objects, and aggregates because it's delightful.

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
      from the values that relate only to it

  One possible valid way to do so is to use Domo library like the following:

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

      Order.new!(
        id: Id --- "156",
        quantity: Quantity --- Kilograms --- 2.5
        note: Note --- "Deliver on Tue"
      )

  And a signature of a custom function to modify the struct becomes like this:

      @spec put_quantity(Order.t(), Order.Quantity.t()) :: Order.t()
      def put_quantity(order, Quantity --- Units --- units) ...
      def put_quantity(order, Quantity --- Kilograms --- kilos) ...

  Thanks to the Domo library, every field of the structure becomes
  a [tagged tuple](https://erlang.org/doc/getting_started/seq_prog.html#tuples)
  consisting of a tag and a value. The tag is a module itself.
  Several tags can be nested, defining valid tag chains. These are playing
  the role of shapes for values of primitive type. That makes it possible
  to perform pattern matching against the shape of the struct's value.
  That enables the dialyzer to validate contracts for the structure itself
  and the structure's field values.

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

  Use `new/1`, `merge/2`, and `put/3` function or their raising versions
  that are all automatically defined for the struct to create a new instance
  and update an existing one.

      alias Order
      alias Order.{Id, Note}

      %{id: Id --- "o123556"}
      |> Order.new!()
      |> Order.put!(:note, Note --- "Deliver on Tue")

  At the compile-time the dialyzer can check if properly tagged values are passed
  as parameters to these functions.

  At the run-time, each function checks the values passed in against the types set
  in the `field/3` macro. In case of mismatch, the functions raise an error.

  That works with tags, and with any other user or system type, you may specify
  for the field. You can introduce tags in the project gracefully,
  taking them in appropriate proportion with the type safe-structs.

  The functions mentioned above can be overridden to make data validations.
  Please, be careful and modify struct with a super(...) call. This call should
  be the last call in the overridden function.

  It's still possible to modify a struct with %{... | s } map syntax and other
  standard functions directly skipping the checks.
  Please, use the functions mentioned above for the type-safety.

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

  We can't make you know the business problem; at the same time,
  the Domo library can help you to model the problem and understand it better.

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
  Defines a struct with all keys enforced, a `new/1`, `merge/2`, `put/2`
  and their bang versions into it.

  The macro defines a struct by passing an `[enforced: true]` option,
  and the `do` block to the `typed_struct` function of the same-named library.
  It's possible to use plugins for the TypedStruct in place,
  see [library's documentation](https://hexdocs.pm/typed_struct) for syntax details.

  The default implementation of the `new!/1` constructor function looks like
  the following:

      def new!(map), do: struct!(__MODULE__, map)

  The `merge!/2` function should be used to update several keys of the existing
  structure at once. The missing keys are ignored.

      def merge!(%__MODULE__{} = s, enumerable), do: ...

  The `put!/2` function should be used to update one key of the existing structure.
  Its definition looks like the following:

      def put!(%__MODULE__{} = s, field, value), do: ...

  Both `new!/1` and `put!/2` have type specs defined from the struct fields.
  Meaning, that the dialyzer can indicate contract break when values with wrong
  tags are used to construct or modify the structure.

  At the run-time the functions check every argument against the type spec
  set for the field with `field/3` macro. And raises or returns an error
  on mismatch of the value type and the field's type.

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
      ...>
      ...> p = Person.new!(%{name: "Sarah Connor"})
      ...> p = Person.put!(p, :name, "Connor")
      ...> {:error, _} = Person.merge(p, name: 9)

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

    fields_kw_spec =
      Enum.reverse(List.wrap(Module.get_attribute(__CALLER__.module, :domo_struct_key_type)))

    field_error_defs = quoted_field_error_funs(fields_kw_spec, __CALLER__)
    put_defs = if not Enum.empty?(fields_kw_spec), do: quoted_put_funs(fields_kw_spec)
    merge_defs = if not Enum.empty?(fields_kw_spec), do: quoted_merge_funs(fields_kw_spec)

    quote location: :keep do
      alias Domo.TypeContract

      require TypedStruct

      @type fn_new_argument ::
              [unquote_splicing(fields_kw_spec)] | %{unquote_splicing(fields_kw_spec)}
      @type fn_new_field_error :: %{field: atom, value: any, type: String.t()}

      TypedStruct.typedstruct([enforce: true], do: unquote(block))

      @spec new!(fn_new_argument()) :: t()
      def new!(enumerable) do
        __raise_mistyped_fields_if_needed(struct!(__MODULE__, enumerable), fn ->
          "new!(#{inspect(enumerable)})"
        end)
      end

      @spec new(fn_new_argument()) :: {:ok, t()} | {:error, {:key_err | :value_err, String.t()}}
      def new(enumerable) do
        with {:ok, s} <- __struct_or_err(enumerable),
             {:ok, s} = res <-
               __struct_or_mistyped_fields_err(s, fn -> "new(#{inspect(enumerable)})" end) do
          res
        else
          err -> err
        end
      end

      defoverridable new!: 1, new: 1

      @spec __struct_or_err(fn_new_argument()) :: {:ok, t()} | {:error, {:key_err, String.t()}}
      defp __struct_or_err(enumerable) do
        try do
          {:ok, struct!(__MODULE__, enumerable)}
        rescue
          err in [ArgumentError] -> {:error, {:key_err, err.message}}
        end
      end

      @spec __format_mistyped_construction_error([fn_new_field_error()], String.t()) :: String.t()
      defp __format_mistyped_construction_error(list, call_site) do
        "Can't construct %#{inspect(__MODULE__)}{...}"
        |> Kernel.<>(if String.length(call_site) == 0, do: "", else: " with " <> call_site)
        |> Kernel.<>("\n")
        |> Kernel.<>(__format_value_type_error(list))
      end

      @spec __format_value_type_error([fn_new_field_error()], padding: boolean) :: String.t()
      defp __format_value_type_error(list, opts \\ [padding: true]) do
        list
        |> Enum.map(&"Unexpected value type for the field #{inspect(&1.field)}. \
The value #{inspect(&1.value)} doesn't match the #{&1.type} type.")
        |> Enum.map(&(if(true == opts[:padding], do: "    ", else: "") <> &1))
        |> Enum.join("\n")
      end

      @spec __struct_or_mistyped_fields_err(t(), (() -> String.t())) ::
              {:ok, t()} | {:error, {:value_err, String.t()}}
      defp __struct_or_mistyped_fields_err(struct, call_site_fn) do
        case __mistyped_fields(Map.from_struct(struct)) do
          [] ->
            {:ok, struct}

          list ->
            {:error, {:value_err, __format_mistyped_construction_error(list, call_site_fn.())}}
        end
      end

      @spec __raise_mistyped_fields_if_needed(t(), (() -> String.t())) :: t()
      defp __raise_mistyped_fields_if_needed(struct, call_site_fn) do
        case __mistyped_fields(Map.from_struct(struct)) do
          [] ->
            struct

          list ->
            raise(
              ArgumentError,
              __format_mistyped_construction_error(list, call_site_fn.())
            )
        end
      end

      @spec __mistyped_fields(fn_new_argument()) :: [fn_new_field_error()]
      defp __mistyped_fields(enumerable) do
        Enum.filter(Enum.map(enumerable, &__field_error/1), &(not is_nil(&1)))
      end

      @spec __field_error({atom, any}) :: fn_new_field_error() | nil
      unquote(field_error_defs)
      defp __field_error({_unknown_field, _value}), do: nil

      unquote(put_defs)
      unquote(merge_defs)
    end
  end

  defp expand_in_block_once({:__block__, meta, fields}, env) do
    {:__block__, meta, Enum.map(fields, &Macro.expand_once(&1, env))}
  end

  defp expand_in_block_once(field, env) do
    Macro.expand_once(field, env)
  end

  defp quoted_field_error_funs(fields_kw_spec, caller_env) do
    fields_kw_spec
    |> Enum.map(fn {field, type} -> {field, Macro.escape(type), Macro.to_string(type)} end)
    |> Enum.map(&quoted_field_error(&1, caller_env))
  end

  defp quoted_field_error({field, type_esc, type_str}, caller_env) do
    caller_env = Macro.escape(caller_env)

    quote do
      defp __field_error({unquote(field) = name, value}) do
        case TypeContract.valid?(value, unquote(type_esc), unquote(caller_env)) do
          true -> nil
          false -> %{field: name, value: value, type: unquote(type_str)}
        end
      end
    end
  end

  defp quoted_merge_funs(fields_spec) do
    struct_keys = Keyword.keys(fields_spec)

    quote location: :keep do
      @spec merge(t(), keyword() | map()) ::
              {:ok, t()} | {:error, {:unexpected_struct | :value_err, String.t()}}
      def merge(%__MODULE__{} = s, enumerable) do
        case __filter_mistyped_fields(enumerable) do
          [] -> {:ok, struct(s, enumerable)}
          list -> {:error, {:value_err, __format_value_type_error(list, padding: false)}}
        end
      end

      def merge(%name{}, _enum) do
        {:error, {:unexpected_struct, "#{inspect(__MODULE__)} structure was expected \
as the first argument and #{inspect(name)} was received."}}
      end

      @spec merge!(t(), keyword() | map()) :: t()
      def merge!(%__MODULE__{} = s, enumerable) do
        case __filter_mistyped_fields(enumerable) do
          [] -> struct(s, enumerable)
          list -> raise(ArgumentError, __format_value_type_error(list, padding: false))
        end
      end

      def merge!(%name{}, _enum),
        do: raise(ArgumentError, "#{inspect(__MODULE__)} structure was expected \
as the first argument and #{inspect(name)} was received.")

      @spec __filter_mistyped_fields(keyword() | map()) :: [fn_new_field_error()] | []
      defp __filter_mistyped_fields(enumerable) do
        enumerable
        |> Enum.filter(fn {key, _value} -> Enum.member?(unquote(struct_keys), key) end)
        |> Enum.into(%{})
        |> __mistyped_fields()
      end

      defoverridable merge!: 2, merge: 2
    end
  end

  defp quoted_put_funs(fields_spec) do
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
        case __field_error({unquote(key), value}) do
          %{} = err -> raise(ArgumentError, __format_value_type_error([err], padding: false))
          nil -> Map.replace!(s, unquote(key), value)
        end
      end

      @spec put(t(), unquote(key), unquote(type)) ::
              {:ok, t()}
              | {:error, {:unexpected_struct | :key_err | :value_err, String.t()}}
      def put(%__MODULE__{} = s, unquote(key), value) do
        case __field_error({unquote(key), value}) do
          %{} = err -> {:error, {:value_err, __format_value_type_error([err], padding: false)}}
          nil -> {:ok, Map.replace!(s, unquote(key), value)}
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
        do: raise(ArgumentError, "#{inspect(__MODULE__)} structure was expected \
as the first argument and #{inspect(name)} was received.")
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
