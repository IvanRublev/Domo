# Domo

> To give the example app a try:
> 1. Clone this repo
> 2. Switch to master version of the Elixir with `asdf local elixir master`
> 3. Change to `example_app` directory and follow instructions from README.md

Domo is a library for modeling data with custom composable types
beyond structs and keyword lists. That enables-compile time verification
of the business domain model consistency.

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

    @spec put_quantity(Order.t(), quantity: float()) :: Order.t()
    def put_quantity(ord, quantity: q) ...

Primitive types of binary and float are universal and have no relation
to the Order struct specifically. That is, any data of that type
can leak into the new struct instance by mistake.
Float type defining quantity reflects no measure from the business domain.
Meaning, that a new requirement to measure quantity in Kilograms or Units
makes space for misinterpretation of the quantity field's value processed
in any part of the app.

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

And a signature of a custom function to modify struct becomes like this:

    @spec put_quantity(Order.t(), Order.Quantity.t()) :: Order.t()
    def put_quantity(ord, Quantity --- Units --- q) ...
    def put_quantity(ord, Quantity --- Kilograms --- q) ...

Thanks to the Domo library, every field of the structure becomes a [tagged tuple](https://erlang.org/doc/getting_started/seq_prog.html#tuples)
consisting of a tag and a value. A tag is a module itself.
Several tags can be nested, defining valid tag chains as a shape for values
of primitive type. That makes it possible to do pattern matching against
the shape of the struct's value. That enables the dialyzer to validate
contracts for the structure itself and the structure's field values.

## Usage

### Setup

To use Domo in your project, add this to your Mix dependencies:

    {:domo, "~> 0.1.0"}

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
See [TypedStruct library documentation](https://hexdocs.pm/typed_struct/) for implementation details.

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

    * `undefined_tag_error_as_warning` - if set tot true, prints warning
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
