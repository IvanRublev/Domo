defmodule AppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :app

  defp parse_post_json(%Plug.Conn{method: "POST"} = conn, _opt) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    body = if body == "", do: List.first(Map.keys(conn.body_params)), else: body

    {params, body} =
      cond do
        is_binary(body) ->
          body = Phoenix.json_library().decode!(body)
          {Map.merge(conn.params, body), body}

        true ->
          {conn.params, body}
      end

    %{conn | params: params, body_params: body}
  end

  defp parse_post_json(conn, _opt), do: conn

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded],
    pass: ["application/json"]

  plug :parse_post_json
  plug Plug.MethodOverride
  plug Plug.Head
  plug AppWeb.Router
end
