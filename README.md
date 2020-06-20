# Domo

[![Build Status](https://travis-ci.com/IvanRublev/domo.svg?branch=master)](https://travis-ci.com/IvanRublev/domo)
[![Method TDD](https://img.shields.io/badge/method-TDD-blue)](#domo)
[![hex.pm version](http://img.shields.io/hexpm/v/domo.svg?style=flat)](https://hex.pm/packages/domo)

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

```elixir
defmodule User do
  type t :: %__MODULE__{id: integer, name: String.t()}

  defstruct [:id, :name]

  def new(id: id, name: name) when is_integer(id) and is_binary(name),
    do: struct!(__MODULE__, id: id, name: name)
end
```

The code written above repeats for almost every entity in the application.
And it'd be great to make it generated automatically reducing the structure
definition to the minimal preferably declarative style.

One way to do this is with the Domo library like that:

```elixir
defmodule User do
  use Domo

  typedstruct do
    field :id, integer
    field :name, String.t()
    field :post_address, :not_given | String.t(), default: :not_given
  end
end
```

Thanks to the declarative syntax from the [TypedStruct](https://hexdocs.pm/typed_struct/),
the type and struct definitions are in the module. What's the Domo library
adds on top is the set of `new/1` `put/1` and `merge/1` functions and their
raising versions `new!/1`, `put!/1`, and `merge!/1`. These functions verify
that arguments are of the field types and then build or modify the struct
otherwise returning an error or raising the `ArgumentError` exception.

The construction with automatic verification of the User struct can
be as immediate as that:

```elixir
User.new!(id: 1, name: "John")
%User{id: 1, name: "John", post_address: :not_given}

User.new!(id: 2, name: nil, post_address: 3)
** (ArgumentError) Can't construct %User{...} with new!([id: 2, name: nil, post_address: 3])
    Unexpected value type for the field :name. The value nil doesn't match the String.t() type.
    Unexpected value type for the field :post_address. The value 3 doesn't match the :not_given | String.t() type.
```

To modify an existing struct the put of merge functions can be used like that:

```elixir
User.put!(user, :name, "John Bongiovi")
%User{id: 1, name: "John Bongiovi", post_address: :not_given}

User.merge!(user, %{name: "John Francis Bongiovi", post_address: :not_given, genre: :rock, albums: 20})
%User{id: 1, name: "John Francis Bongiovi", post_address: :not_given}
```

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

```elixir
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
```

The additional tuples here and there seem cumbersome. One way to make
the tag definition elegant is with `deftag/2` macro.
We can rewrite the code to more compact way like this:

```elixir
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
```

In the example above the `deftag/2` macro defines the tag - Id module and
the type t :: {Id, integer} in it.

### Third dimension for structures with tag chains 🍿

Let's say one of the business requirements is to register the quantity
of the Order in kilograms or units. That means that the structure's quantity
field value can be float or integer. It'd be great to keep the kind
of quantity alongside the value for the sake of local reasoning in different
parts of the application. One possible way to do that is to use tag chains
like that:

```elixir
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
```

In the example above the construction with invalid quantity raises
the exception. And if there is no `to_string` function for one of the quantity
kinds defined the no function clause matching error raises in run-time.

That's how possible to define valid states for `Order` with `typedstruct/1`
and `deftag/2` macro and keep the structs consistent throughout the app
with type verifications in autogenerated `new/1`, `put/1`, and `merge/1` functions.

## Usage

### Setup

To use Domo in your project, add this to your Mix dependencies:

```elixir
{:domo, "~> #{Mix.Project.config()[:version]}"}
```

To avoid `mix format` putting extra parentheses around macro calls, 
you can add to your `.formatter.exs`:

```elixir
[
  ...,
  import_deps: [:domo]
]
```

### General usage

#### Define a structure

To describe a structure with field value contracts, use Domo, then define
your struct with a `typedstruct/1` block.

```elixir
defmodule Wonder do
  use Domo

  @typedoc "A world wonder. Ancient or contemporary."
  typedstruct do
    field :id, integer
    field :name, String.t(), default: ""
  end
end
```

Define each field with `field/3` macro. The generated structure has all fields
enforced, default values if specified for fields, and type `t()` constructed
from field types. See TypedStruct library documentation for implementation
details.

Same time the generated structure has `new/1`, `merge/2`, and `put/3` functions
or their raising versions automatically defined. These functions have specs
with field types defined. Use these functions to create a new instance
and update an existing one.

```elixir
%{id: 123556}
|> Wonder.new!()
|> Wonder.put!(:name, "Eiffel tower")
%Wonder{id: 123556, name: "Eiffel tower"}
```

At the compile-time, the dialyzer can do static analysis of functions
contract.
At the run-time, each function checks the values passed in against
the types set in the `field/3` macro. In case of mismatch, the functions
raise an `ArgumentError`.

#### Define a tag to enrich the field's type

To define a tag on the top level of a file import Domo, then give
the tag name and type associated value with `deftag/2` macro.

```elixir
import Domo
deftag Height do
  for_type __MODULE__.Meters.t() | __MODULE__.Foots.t()

  deftag Meters, for_type: float
  deftag Foots, for_type: float
end
```

Any tag is a module by itself. Type `t()` of the tag is a [tagged tuple](https://erlang.org/doc/getting_started/seq_prog.html#tuples).
It's possible to have a tag or a tag chain added to a value like the following:

```elixir
alias Height.{Meters, Foots}
m = {Height, {Meters, 324.0}}
f = {Height, {Foots, 1062.992}}
```

The tag chain attached to the value is a series of nested tagged tuples where
the value is in the core. It's possible to extract the value
with pattern matching.

```elixir
{Height, {Meters, 324.0}} == m

@spec to_string(Height.t()) :: String.t()
def to_string({Height, {Meters, val}}), do: to_string(val) <> " m"
def to_string({Height, {Foots, val}}), do: to_string(val) <> " ft"
```

#### Combine struct and tags

To refine different kinds of field values, use the tag's `t()` type like that:

```elixir
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
```

The tag can be aliased or defined inline. Use autogenerated functions
to build or modify struct having types verification.

```elixir
import Domo
alias Height.Meters

Wonder.new!(id: 145, name: "Eiffel tower", height: {Height, {Meters, 324.0}})
%Wonder{height: {Height, {Height.Meters, 324.0}}, id: 145, name: "Eiffel tower"}
```

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

```elixir
config :domo, :unexpected_type_error_as_warning, true
```

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

When one uses a remote type for the field of a struct, the runtime type check
will work properly only if the remote type's module is compiled into
the .beam file on the disk, which means, that modules generated in memory
are not supported. That's because of the way the Erlang functions load types.

We may not know your business problem; at the same time, the Domo library
can help you to model the problem and understand it better.

## Adoption strategies

It's possible to start with typedstruct macro to define structs in
a compact declarative way, use `new!/1`, `put!/1`, and `merge!/1` to modify
structures to enable type-checking, and finally introduce tags
with `deftag/2` for structure fields. These tools are for appropriate
use according to the problem. Give them a try and see how far you can go.

## Performance 🐢

It may seem that the current version of the library is plodding. And it may
look like non-performant to run in production. And even more, it may seem
that the library degrades users experience dramatically.
Actually, it's good enough for "make it work", and it's applicable in various
business contexts.
There is an excellent room for speed improvements now.

    Generate 10000 inputs, may take a while.
    =========================================

    Construction of a struct
    =========================================
    Operating System: macOS
    CPU Information: Intel(R) Core(TM) i7-4870HQ CPU @ 2.50GHz
    Number of Available Cores: 8
    Available memory: 16 GB
    Elixir 1.10.0
    Erlang 22.2.3

    Benchmark suite executing with the following configuration:
    warmup: 2 s
    time: 5 s
    memory time: 0 ns
    parallel: 1
    inputs: none specified
    Estimated total run time: 14 s

    Benchmarking __MODULE__.new!(arg)...
    Benchmarking struct!(__MODULE__, arg)...

    Name                               ips        average  deviation         median         99th %
    struct!(__MODULE__, arg)       10.93 K      0.0915 ms    ±56.64%      0.0930 ms        0.22 ms
    __MODULE__.new!(arg)          0.0161 K       62.09 ms     ±5.32%       61.22 ms       79.17 ms

    Comparison: 
    struct!(__MODULE__, arg)       10.93 K
    __MODULE__.new!(arg)          0.0161 K - 678.57x slower +62.00 ms

    A struct's field modification
    =========================================

    Benchmark suite executing with the following configuration:
    warmup: 2 s
    time: 5 s
    memory time: 0 ns
    parallel: 1
    inputs: none specified
    Estimated total run time: 14 s

    Benchmarking __MODULE__.put!(tweet, :user, arg)...
    Benchmarking struct!(tweet, user: arg)...

    Name                                         ips        average  deviation         median         99th %
    struct!(tweet, user: arg)                12.64 K      0.0791 ms    ±67.17%      0.0810 ms        0.20 ms
    __MODULE__.put!(tweet, :user, arg)      0.0440 K       22.75 ms     ±2.52%       22.70 ms       25.01 ms

    Comparison: 
    struct!(tweet, user: arg)                12.64 K
    __MODULE__.put!(tweet, :user, arg)      0.0440 K - 287.64x slower +22.67 ms

    Merge map into a struct
    =========================================

    Benchmark suite executing with the following configuration:
    warmup: 2 s
    time: 5 s
    memory time: 0 ns
    parallel: 1
    inputs: none specified
    Estimated total run time: 14 s

    Benchmarking __MODULE__.merge!(tweet, map)...
    Benchmarking struct(tweet, map)...

    Name                                    ips        average  deviation         median         99th %
    struct(tweet, map)                  12.60 K      0.0793 ms    ±66.60%      0.0810 ms       0.199 ms
    __MODULE__.merge!(tweet, map)      0.0439 K       22.77 ms     ±2.15%       22.72 ms       24.25 ms

    Comparison: 
    struct(tweet, map)                  12.60 K
    __MODULE__.merge!(tweet, map)      0.0439 K - 287.02x slower +22.69 ms

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

* [x] Check if the field values passed as an argument to the `new/1`, 
      and `put/3` matches the field types defined in `typedstruct/1`.

* [x] Support the keyword list as a possible argument for the `new!/1`.

* [x] Add module option to put a warning in the console instead of raising 
      of the `ArgumentError` exception on value type mismatch.

* [x] Make global environment configuration options to turn errors into 
      warnings that are equivalent to module ones.

* [ ] Make the `new(!)/1`, `put(!)/3`, and `merge(!)/2` speed to be 30% closer
      to the speed of the `struct!/2`.

* [ ] Add documentation to the generated `new(!)/1`, `put(!)/3`, and `merge(!)/2`
      functions in struct.

* [ ] Make the `typedstruct/1` to raise an error on default value that mismatches 
      the field's type at the end of compilation (At the moment it's checked
      during the construction of the struct with default values).

## License

Copyright © 2020 Ivan Rublev

This project is licensed under the [MIT license](LICENSE).
