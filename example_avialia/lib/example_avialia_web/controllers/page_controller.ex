defmodule ExampleAvialiaWeb.PageController do
  use ExampleAvialiaWeb, :controller

  alias ExampleAvialia.Cargos
  alias ExampleAvialia.Boardings

  def index(conn, _params) do
    render(conn, "index.html", build_assigns())
  end

  def build_assigns(args \\ []) do
    Keyword.merge(build_boarding_assigns(args), build_cargo_assigns(args))
  end

  # === Boardings ===

  def new_boarding(conn, params) do
    form = params["passenger"]

    fields = %{
      first_name: form["first_name"],
      last_name: form["last_name"],
      flight: form["flight"],
      seat: form["seat"]
    }

    case Boardings.create_passenger(fields) do
      {:ok, passenger} -> render(conn, "index.html", build_assigns(passenger_changeset: Boardings.passenger_changeset(passenger)))
      {:error, changeset} -> render(conn, "index.html", build_assigns(passenger_changeset: changeset))
    end
  end

  def delete_boarding(conn, params) do
    if id = to_integer(params["id"]) do
      id
      |> Boardings.get_passenger!()
      |> Boardings.delete_passenger()
    end

    redirect(conn, to: Routes.page_path(conn, :index))
  end

  defp build_boarding_assigns(args) do
    passenger_changeset = args[:passenger_changeset] || Boardings.passenger_changeset()

    passengers_list =
      Boardings.list_passengers!()
      |> Enum.sort_by(&{&1.flight, &1.seat})

    [
      passenger_changeset: passenger_changeset,
      passengers_list: passengers_list
    ]
  end

  # === Cargos ===

  def new_cargo(conn, params) do
    form = params["shipment"]

    document_titles =
      case form["document_names"] do
        "" -> []
        titles_string -> titles_string |> String.split(",") |> Enum.map(&String.trim/1)
      end

    documents_attributes = Enum.map(document_titles, &%{title: &1})

    fields = %{
      flight: form["flight"],
      kind: maybe_apply(&Cargos.build_shipment_kind/2, [form["shipment_kind_variant"], form["shipment_kind_id"]]),
      weight: maybe_apply(&Cargos.build_shipment_weight/2, [form["weight_measurement"], to_integer(form["weight_count"])]),
      documents: documents_attributes
    }

    case Cargos.create_shipment(fields) do
      {:ok, _passenger} -> render(conn, "index.html", build_assigns())
      {:error, changeset} -> render(conn, "index.html", build_assigns(shipment_errors: changeset.errors))
    end
  end

  def delete_cargo(conn, params) do
    if id = to_integer(params["id"]) do
      id
      |> Cargos.get_shipment!()
      |> Cargos.delete_shipment()
    end

    redirect(conn, to: Routes.page_path(conn, :index))
  end

  defp maybe_apply(fun, values) do
    unless Enum.any?(values, &is_nil(&1)) do
      apply(fun, values)
    end
  end

  defp build_cargo_assigns(args) do
    shipment_errors = args[:shipment_errors] || []
    measurements_reference = args[:measurements_reference] || Cargos.get_measurements_reference()

    measurements =
      measurements_reference
      |> Enum.sort_by(fn {_name, kilograms} -> kilograms end)
      |> Enum.map(fn {name, kilos} -> {pretty_measurement(name, kilos), name} end)
      |> Enum.into([])

    shipment_kind_variants =
      Cargos.get_shipment_kind_variants()
      |> Enum.map(&{&1, pretty_shipment_kind_variant(&1)})
      |> Enum.into([])

    shipments_list =
      Cargos.list_shipment_attributes(measurements_reference)
      |> Enum.sort_by(&{&1.flight, &1.id})
      |> Enum.map(&prettify_shipment_attributes/1)

    [
      shipment_errors: shipment_errors,
      measurements_list: measurements,
      shipment_kind_variants: shipment_kind_variants,
      shipments_list: shipments_list
    ]
  end

  defp pretty_measurement(name, kilos) do
    "#{measurement_string(name)} (#{kilos}kg/pcs)"
  end

  defp measurement_string(name) do
    name
    |> String.split("|", trim: true)
    |> List.last()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp pretty_shipment_kind_variant(variant) do
    variant
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp prettify_shipment_attributes(attributes) do
    attributes
    |> Map.put(:weight_measure, pretty_weight_measure(attributes.weight_measure))
    |> Map.put(:weight_kilos, pretty_weight_kilos(attributes.weight_kilos))
    |> Map.put(:documents_count, pretty_documents_count(attributes.documents_count))
  end

  defp pretty_weight_measure({measurement, count}) do
    "#{count} #{measurement_string(measurement)}"
  end

  defp pretty_weight_kilos(kilos) do
    "#{kilos} Kg"
  end

  defp pretty_documents_count(count) do
    "#{count} doc(s)"
  end

  defp to_integer(string) do
    case Integer.parse(string) do
      {integer, _rest} -> integer
      _ -> nil
    end
  end
end
