# Domo

[![Build Status](https://travis-ci.com/IvanRublev/domo.svg?branch=master)](https://travis-ci.com/IvanRublev/domo)
[![Method TDD](https://img.shields.io/badge/method-TDD-blue)](#domo)
[![hex.pm version](http://img.shields.io/hexpm/v/domo.svg?style=flat)](https://hex.pm/packages/domo)

⚠️ This library generates code for structures that can bring suboptimal compilation times increased to approx 20%. Please, evaluate before use ⚠️

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

```elixir
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
```

The code written above repeats for almost every entity in the application.
And it'd be great to make it generated automatically, reducing the structure
definition to the minimal and declarative.

One way to do this is with the Domo library that plays nicely together
with [TypedStruct](https://hexdocs.pm/typed_struct/) like the following:

```elixir
defmodule User do
  use Domo
  use TypedStruct

  typedstruct enforce: true do
    field :id, integer
    field :name, String.t()
    field :post_address, :not_given | String.t(), default: :not_given
  end
end
```

Thanks to the `typedstruct` macro from the same named library the type
and struct definitions are in the module.

What the Domo adds on top are the constructor function `new/1` and
the `ensure_type!/1` function. These functions ensure that arguments
are of the field types otherwise raising the `ArgumentError` exception.

Domo adds `new_ok/1` and `ensure_type_ok/1` versions returning ok-error
tuple too.

The construction with automatic type ensurance of the User struct can
be as immediate as that:

```elixir
User.new(id: 1, name: "John")
%User{id: 1, name: "John", post_address: :not_given}

User.new(id: 2, name: nil, post_address: 3)
** (ArgumentError) Can't construct %User{...} with new!([id: 2, name: nil, post_address: 3])
    Unexpected value type for the field :name. The value nil doesn't match the String.t() type.
    Unexpected value type for the field :post_address. The value 3 doesn't match the :not_given | String.t() type.
```

After the modification of the existing struct its type can be ensured
like the following:

```elixir
user
|> User.struct!(name: "John Bongiovi")
|> User.ensure_type!()
%User{id: 1, name: "John Bongiovi", post_address: :not_given}
```

## How it works

For each `MyModule` struct Domo library generates a `MyModule.TypeEnsurer` at
the compile time. The latter verifies that the given fields matches the
type of `MyModule` and is used by `new/1` constructor and other functions.

If the field is of the struct type that uses Domo as well, then the ensurance
of the field's value delegates to the `TypeEnsurer` of that struct.

Domo library uses `:domo_compiler` to generate `TypeEnsurer` modules code. See
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

```elixir
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
```

### Third dimension for structures with tag chains and ---/2 operator 🍿

Let's say one of the business requirements is to register the quantity
of the Order in units or kilograms. That means that the structure's quantity
field value can be integer or float. It'd be great to keep the kind
of quantity alongside the value for the sake of local reasoning in different
parts of the application. One possible way to do that is to use tag chains
like that:

```elixir
defmodule Order do
  use Domo

  defmodule Id, do: @type t :: {__MODULE__, integer}

  defmodule Quantity do
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
```

And to construct the `Order` specifying quantity with a tag chain like that:

```elixir
alias Order.{Id, Quantity}
alias Order.Quantity.{Kilograms, Units}

Order.new(id: {Id, 158}, name: "Fruits", quantity: {Quantity, {Kilograms, 12.5}})
%Order{
  id: {Order.Id, 158},
  name: "Fruits",
  quantity: {Order.Quantity, {Order.Quantity.Kilograms, 12.5}}
}
```

To remove extra brackets from the tag chain definition, one can use the `---/2`
operator from the `Domo.TaggedTuple` module. Then one can rewrite the above
example as that:

```elixir
use Domo.TaggedTuple
alias Order.{Id, Quantity}
alias Order.Quantity.{Kilograms, Units}

Order.new(id: Id --- 158, name: "Fruits", quantity: Quantity --- Kilograms --- 12.5)
%Order{
  id: {Order.Id, 158},
  name: "Fruits",
  quantity: {Order.Quantity, {Order.Quantity.Kilograms, 12.5}}
}
```

It's possible to use `---/2` even in pattern matchin like the following:

```elixir
def to_string(%Order{quantity: Quantity --- Kilograms --- kilos}), do: to_string(kilos) <> "kg"
def to_string(%Order{quantity: Quantity --- Units --- kilos}), do: to_string(kilos) <> " units"
```

## Usage

### Setup

To use Domo in your project, add this to your `mix.exs` dependencies:

```elixir
{:domo, "~> #{Mix.Project.config()[:version]}"}
```

And the folowing line to the compilers:

```elixir
compilers: Mix.compilers() ++ [:domo_compiler],
```

To avoid `mix format` putting extra parentheses around macro calls,
you can add to your `.formatter.exs`:

```elixir
[
  import_deps: [:domo]
]
```

### Setup for Phoenix hot reload

If you intend to call generated functions of structs using Domo from a Phoenix controller, add the following line to the endpoint's configuration in `config.exs` file:

```elixir
config :my_app, MyApp.Endpoint,
  reloadable_compilers: [:phoenix] ++ Mix.compilers() ++ [:domo_compiler],
```

Otherwise type changes wouldn't be hot-reloaded by Phoenix.

### General usage

#### Define a structure

To describe a structure with field value contracts, use Domo, then define
your struct and its type.

```elixir
defmodule Wonder do
  use Domo

  @typedoc "A world wonder. Ancient or contemporary."
  @enforce_keys [:id]
  defstruct [:id, :name]

  @type t :: %__MODULE__{id: integer, name: nil | String.t()}
end
```

The generated structure has `new/1`, `ensure_type!/1` functions
and their non raising `new_ok/1` and `ensure_type_ok/1` versions
automatically defined. These functions have specs with field types defined.
Use these functions to create a new instance and update an existing one.

```elixir
%{id: 123556}
|> Wonder.new()
|> Wonder.struct!(name: "Eiffel tower")
%Wonder{id: 123556, name: "Eiffel tower"}
```

At the run-time, each function checks the values passed in against
the fields types set in the `t()` type. In case of mismatch, the functions
raise an `ArgumentError`.

#### Define a tag to enrich the field's type

To define a tag define a module given the tag name and its type as a tuple
of module name and associated value.

```elixir
use Domo.TaggedTuple
defmodule Height do
  @type t :: {__MODULE__, __MODULE__.Meters.t() | __MODULE__.Foots.t()}

  defmodule Meters, do: @type t :: {__MODULE__, float}
  defmodule Foots, do: @type t :: {__MODULE__, float}
end
```

Type `t()` of the tag is a [tagged tuple](https://erlang.org/doc/getting_started/seq_prog.html#tuples).
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

#### Combine struct, tags, and `---/2` operator

To refine different kinds of field values, use the tag's `t()` type like that:

```elixir
defmodule Wonder do
  use Domo

  @typedoc "A world wonder. Ancient or contemporary."
  @enforce_keys [:id, :height]
  defstruct [:id, name: "", :height]

  @type t :: %__MODULE__{id: integer, name: String.t(), height: Height.t()}
end
```

The tag can be aliased or defined inline. Add tag chains to the value 
with `---/2` operator. Use autogenerated functions to build or modify struct
having types verification.

```elixir
use Domo.TaggedTuple
alias Height.Meters

Wonder.new(id: 145, name: "Eiffel tower", height: Height --- Meters --- 324.0)
%Wonder{height: {Height, {Height.Meters, 324.0}}, id: 145, name: "Eiffel tower"}
```

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

```elixir
use Domo.TaggedTuple
alias Order.Id

identifier
|> untag!(Id)
|> String.graphemes()
|> Enum.intersperse("_")
|> Enum.join()
|> tag(Id)
```

## Limitations

Call to Domo generated `new/1` function from macros is not supported. 
F.e. it's not possible to define a default value in an Ecto schema like that. 
Same time it's possible to ensure that struct value matches the type with a call to `ensure_type/1` from `changeset/2` function of the schema.

The recursive types like `@type t :: :end | {integer, t}` are not supported.

Domo doesn't check struct fields default value explicitly; instead, 
it fails when one creates a struct with wrong defaults.

## Migration

To complete the migration to a new version of Domo, please, clean and recompile 
the project with `mix clean --deps && mix compile` command.

## Performance 🐢

On the average, the current version of the library makes struct operations 
about 20% sower what may seem plodding. And it may look like non-performant
to run in production.

It's not that. The library ensures the correctness of data types at runtime and
it comes with the price of computation. As the result users get the application 
with correct states at every update that is valid in many business contexts.

    Generate 10000 inputs, may take a while.
    =========================================

    Construction of a struct
    =========================================
    Operating System: macOS
    CPU Information: Intel(R) Core(TM) i7-4870HQ CPU @ 2.50GHz
    Number of Available Cores: 8
    Available memory: 16 GB
    Elixir 1.11.0
    Erlang 23.1.5

    Benchmark suite executing with the following configuration:
    warmup: 2 s
    time: 5 s
    memory time: 0 ns
    parallel: 1
    inputs: none specified
    Estimated total run time: 14 s

    Benchmarking __MODULE__.new(arg)...
    Benchmarking struct!(__MODULE__, arg)...

    Name                               ips        average  deviation         median         99th %
    struct!(__MODULE__, arg)       13.66 K       73.21 μs    ±58.79%          76 μs         152 μs
    __MODULE__.new(arg)            10.97 K       91.12 μs    ±46.25%          93 μs         174 μs

    Comparison: 
    struct!(__MODULE__, arg)       13.66 K
    __MODULE__.new(arg)            10.97 K - 1.24x slower +17.91 μs

    A struct's field modification
    =========================================
    Operating System: macOS
    CPU Information: Intel(R) Core(TM) i7-4870HQ CPU @ 2.50GHz
    Number of Available Cores: 8
    Available memory: 16 GB
    Elixir 1.11.0
    Erlang 23.1.5

    Benchmark suite executing with the following configuration:
    warmup: 2 s
    time: 5 s
    memory time: 0 ns
    parallel: 1
    inputs: none specified
    Estimated total run time: 14 s

    Benchmarking %{tweet | user: arg} |> __MODULE__.ensure_type!()...
    Benchmarking struct!(tweet, user: arg)...

    Name                                                        ips        average  deviation         median         99th %
    struct!(tweet, user: arg)                               15.60 K       64.09 μs    ±65.30%          63 μs         143 μs
    %{tweet | user: arg} |> __MODULE__.ensure_type!()       12.69 K       78.80 μs    ±53.78%          81 μs         159 μs

    Comparison: 
    struct!(tweet, user: arg)                               15.60 K
    %{tweet | user: arg} |> __MODULE__.ensure_type!()       12.69 K - 1.23x slower +14.72 μs

## Contributing

1. Fork the repository and make a feature branch

2. Working on the feature, please add typespecs

3. After working on the feature format code with

       mix format

   run the tests to ensure that all works as expected with

       mix test

   and make sure that the code coverage is ~100% what can be seen with

       mix coveralls.html

4. Make a PR to this repository

## Changelog 

### 1.2.2
* Add support for `new/1` calls at compile time f.e. to specify default values

### 1.2.1
* Domo compiler is renamed to `:domo_compiler`
* Compile `TypeEnsurer` modules only if struct changes or dependency type changes 
* Phoenix hot-reload with `:reloadable_compilers` option is fully supported

### 1.2.0 
* Resolve all types at compile time and build `TypeEnsurer` modules for all structs
* Make Domo library work with Elixir 1.11.x and take it as the required minimum version
* Introduce `---/2` operator to make tag chains with `Domo.TaggedTuple` module

### 0.0.x - 1.0.x 
* MVP like releases, resolving types at runtime. Adds `new` constructor to a struct

## Roadmap

* [x] Check if the field values passed as an argument to the `new/1`, 
      and `put/3` matches the field types defined in `typedstruct/1`.

* [x] Support the keyword list as a possible argument for the `new/1`.

* [x] Add module option to put a warning in the console instead of raising 
      of the `ArgumentError` exception on value type mismatch.

* [x] Make global environment configuration options to turn errors into 
      warnings that are equivalent to module ones.

* [x] Move type resolving to the compile time.

* [x] Keep only bare minimum of generated functions that are `new/1`,
      `ensure_type!/1` and their _ok versions.

* [x] Make the `new/1` and `ensure_type!/1` speed to be less or equal 
      to 1.5 times of the `struct!/2` speed.

* [x] Support `new/1` calls in macros to specify default values f.e. in other 
      structures. That is to check if default value matches type at compile time.

* [ ] Support `contract/1` macro to specify a struct field value's contract 
      with a boolean function.

* [ ] Make a plugin for `TypedStruct` to specify a contract in the filed definition

* [ ] Evaluate full recompilation time for 1000 structs using Domo.

* [ ] Add use option to specify names of the generated functions.

* [ ] Add documentation to the generated for `new(_ok)/1`, and `ensure_type!(_ok)/1`
      functions in a struct.


## License

Copyright © 2021 Ivan Rublev

This project is licensed under the [MIT license](LICENSE).
()