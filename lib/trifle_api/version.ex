defmodule TrifleApi.Version do
  @api_version "v1"

  def api_version, do: @api_version

  def server_version do
    case Application.spec(:trifle, :vsn) do
      nil -> "0.0.0-dev"
      vsn -> to_string(vsn)
    end
  end
end
