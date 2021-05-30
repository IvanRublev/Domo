# Avialia

Example app from the aviation domain. It demonstrates how one can apply Domo library
to share a kernel on types between application models in a microservice setup.

It doesn't use Ecto for simplicity; all data persists in memory while the server runs.

To start your Phoenix server:

  * Install elixir: https://elixir-lang.org/install.html
  * Install dependencies with `mix deps.get`
  * Install Node.js dependencies with `npm install` inside the `assets` directory
  * Start Phoenix endpoint with `mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.
Board passengers and add baggage or commercial cargo to the flight.
