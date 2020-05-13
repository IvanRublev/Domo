# Domo

> This is an experimental library to play with for fun and joy.

> To give the [example app](example_app/) a try:
> 1. Clone this repo
> 2. Switch to the master version of the Elixir with `asdf local elixir master`
> 3. Change to `example_app` directory and follow instructions from README.md

**⚠️ Preview, requires Elixir 1.11.0-dev to run**

--------------

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

```elixir
%Order{
  id: "156",
  quantity: 2.5
  note: "Deliver on Tue"
}
```

and modification of the struct's data can be done with a function of
the following signature:

```elixir
@spec put_quantity(Order.t(), float()) :: Order.t()
def put_quantity(order, quantity) ...
```

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

```elixir
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
```

Then the construction of the struct becomes like this:

```elixir
Order.new!(
  id: Id --- "156",
  quantity: Quantity --- Kilograms --- 2.5
  note: Note --- "Deliver on Tue"
)
```

And a signature of a custom function to modify the struct becomes like this:

```elixir
@spec put_quantity(Order.t(), Order.Quantity.t()) :: Order.t()
def put_quantity(order, Quantity --- Units --- units) ...
def put_quantity(order, Quantity --- Kilograms --- kilos) ...
```

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

```elixir
{:domo, "~> 0.0.8"}
```

To avoid `mix format` putting parentheses on tagged tuples definitions
made with `---/2` operator, you can add to your `.formatter.exs`:

```elixir
[
  ...,
  import_deps: [:typed_struct]
]
```

### General usage

#### Define a tag

To define a tag on the top level of a file import `Domo`, then define the
tag name and type associated value with `deftag/2` macro.

```elixir
import Domo

deftag Title, for_type: String.t()
deftag Height do
  for_type: __MODULE__.Meters.t() | __MODULE__.Foots.t()

  deftag Meters, for_type: float
  deftag Foots, for_type: float
end
```

Any tag is a module by itself. Type `t()` of the tag is a tagged tuple.
When defining a tag in a block form, you can specify the associated value
type through the `for_type/1` macro.

To add a tag or a tag chain to a value use `---/2` macro.

```elixir
alias Height.{Meters, Foots}

t = Title --- "Eiffel tower"
m = Height --- Meters --- 324.0
f = Height --- Foots --- 1062.992
```

Under the hood, the tag chain is a series of nested tagged tuples where the
value is in the core. Because of that, you can use the `---/2` macro
in pattern matching.

```elixir
{Height, {Meters, 324.0}} == m

@spec to_string(Height.t()) :: String.t()
def to_string(Height --- Meters --- val), do: to_string(val) <> " m"
def to_string(Height --- Foots --- val), do: to_string(val) <> " ft"
```

Each tag module has type `t()` of tagged tuple with the name of tag itself
and a value type specified with `for_type`. Use `t()` in the function spec to
inform the dialyzer about the tagged argument.

#### Define a structure

To define a structure with field value's contracts, use `Domo`, then define
your struct with a `typedstruct/1` block.

```elixir
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
```

Each field is defined through `field/3` macro. The generated structure has
all fields enforced, default values specified by `default:` key,
and type t() constructed with field types.
See [TypedStruct library documentation](https://hexdocs.pm/typed_struct/)
for implementation details.

Use `new/1`, `merge/2`, and `put/3` function or their raising versions
that are all automatically defined for the struct to create a new instance
and update an existing one.

```elixir
alias Order
alias Order.{Id, Note}

%{id: Id --- "o123556"}
|> Order.new!()
|> Order.put!(:note, Note --- "Deliver on Tue")
```

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

```elixir
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
```

### Pipeland

To add a tag or a tag chain to a value in a pipe use `tag/2` macro
and to remove use `untag!/2` macro appropriately.

For instance:

```elixir
import Domo
alias Order.Id

identifier
|> untag!(Id)
|> String.graphemes()
|> Enum.intersperse("_")
|> Enum.join()
|> tag(Id)
```

## Limitations

We can't make you know the business problem; at the same time,
the Domo library can help you to model the problem and understand it better.

## Limitations

We can't make you know the business problem, same time the Domo library
can help you to model the problem and understand it better.

## Contributing

1. Fork the repository and make a feature branch

2. Working on the feature, please add typespecs

3. After working on the feature format code with

       mix format

   run the tests and static analyzers to ensure that all works as expected with

       mix test && mix dialyzer

   and make sure that the code coverage is ~100% what can be seen with

       mix coveralls.html

4. Make a PR to this repository

## Roadmap

* [x] Check if the field values passed as argument to the `new/1`, and `put/3`
      matches the field types defined in `typedstruct/1`.

* [x] Add keyword list as a possible argument for `new!/1`.

* [ ] Add documentation to the generated `new(!)/1`, `put(!)/3`, and `merge(!)/2` 
      functions in struct.

* [ ] Make the `typedstruct/1` to raise an error on default value that mismatches 
      the field's type at the end of compilation (At the moment it's checked 
      during the construction of the struct with default values). 

* [ ] Add module option to put warning in the counsole instead of raising 
      of the ArgumentError on value type mismatch.

* [ ] Make global environment configuration options to turn errors into warnings
      that are equivalent to module ones.

## License

Copyright © 2020 Ivan Rublev

This project is licensed under the [MIT license](LICENSE).
