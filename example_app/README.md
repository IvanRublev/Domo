# Order Processor App

Example Phoenix app to demonstrate Domo library usage for domain modeling. 

The app is from a domain of a small delivery service firm.
It can receive a delivery Order with an API endpoint and store the Order 
in the database.
It calculates the weight of the list of specified orders in kilograms 
to estimate what vehicle can deliver them.

You can play with primitive data tags. F.e. you can add a new possible type 
of measurement to Order struct, or mix up the construction of the Order struct with existing one.
Run `mix dialyzer` to get insights about changes needed in the codebase 
(it takes some time during the first run).

## Starting the server

To start your Phoenix server:

  * Run a PostgreSQL docker container with `docker run -d --name "domo_example_app_db" -p 15678:5432 postgres:latest`
  * Install dependencies with `mix deps.get`
  * Setup database with `mix ecto.setup`
  * Start Phoenix endpoint with `mix phx.server`

## Register and estimate orders

To add several orders of different quantity:

    curl --request POST --url http://localhost:4000/add_order --header 'content-type: application/json' \
      --data '{
        "id": "152",
        "note": "Deliver on Tue",
        "units": {
            "kind": "boxes",
            "count": 3
        }
    }'

    curl --request POST --url http://localhost:4000/add_order --header 'content-type: application/json' \
      --data '{
        "id": "160",
        "note": "Deliver on Tue",
        "units": {
            "kind": "packages",
            "count": 15
        }
    }'

    curl --request POST --url http://localhost:4000/add_order --header 'content-type: application/json' \
      --data '{
        "id": "171",
        "kilograms": 25.3
    }'

To list all orders:

    curl --request GET --url http://localhost:4000/all

And calculate the weight of several orders together:

    curl --request POST \
      --url 'http://localhost:4000/kilogrammize?=' \
      --header 'content-type: application/json' \
      --data '{
      "orders": ["ord00000152", "ord00000160", "ord00000171"]
    }'

## Learn more

  * Domo [library documentation](https://hexdocs.pm/domo/)
  * Domain Modelling Made Functional [book by Scott Wlaschin](https://pragprog.com/book/swdddf/domain-modeling-made-functional)
  * [Awesome Domain-Driven Design](https://github.com/heynickc/awesome-ddd#elixir) on GitHub
