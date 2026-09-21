defmodule Trifle.NetworkGatewayStub do
  def configure(connection) do
    notify({:configure, connection})

    case Application.get_env(:trifle, :gateway_stub_configure, {:ok, %{}}) do
      function when is_function(function, 1) -> function.(connection)
      result -> result
    end
  end

  def status(connection) do
    case Application.get_env(:trifle, :gateway_stub_status, %{
           "state" => "Running",
           "enrolled" => true,
           "hostname" => "trifle.test.ts.net",
           "ips" => ["100.64.0.5"]
         }) do
      function when is_function(function, 1) -> function.(connection)
      status -> {:ok, status}
    end
  end

  def put_route(route),
    do:
      (
        notify({:route, route})
        {:ok, %{}}
      )

  def open_stream(route) do
    notify({:open_stream, route})

    case Application.get_env(:trifle, :gateway_stub_stream) do
      function when is_function(function, 1) -> function.(route)
      _ -> {:error, :test_no_stream}
    end
  end

  defp notify(message) do
    if pid = Application.get_env(:trifle, :gateway_stub_owner), do: send(pid, message)
  end
end
