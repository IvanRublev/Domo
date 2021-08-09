# ExampleAvialia

This example demonstrates how Domo can be used to validate model invariants 
of an air carrier company domain.

It has two contexts board passengers and cargo shipments backed 
by two database repositories respectfully. That is to demonstrate how Domo 
can be applied in microservices setup when these two context are extracted
to two apps.

The application persists the changeset validated by Domo if it matches
appropriate schema `t()` type definition and associated preconditions. 
It shows changeset's errors prepared by Domo to user otherwise.

To open application start server and visit [`localhost:4000`](http://localhost:4000) 
from your browser. You can enter some data, see errors, persist or delete records.

Domo can be applied to build and validate any struct defined with `t()` type by itself.
Because each struct with `use Domo` automatically gets `new/1`, `ensure_type!/1/2` 
functions and their `*_ok` versions.

You can build and validate `Passenger` struct directly with Domo with the following:

`iex -S mix`

```
alias ExampleAvialia.Boardings.Passenger

p = Passenger.new(flight: "ALA-1215", first_name: "John", last_name: "Smith", seat: "5C")

Passenger.ensure_type!(%{p | flight: "invalid"})

alias ExampleAvialia.Cargos.Shipment

{:ok, s} = Shipment.new_ok(flight: "ALA-1215", kind: {:passenger_baggage, "5C"}, weight: {:kilograms, 29}, documents_count: 0, documents: [])

Shipment.ensure_type_ok(%{s | kind: {:passenger_baggage, "invalid"}}, maybe_filter_precond_errors: true)
```

### To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Install Node.js dependencies with `npm install` inside the `assets` directory
  * Start Phoenix endpoint with `mix phx.server`

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
