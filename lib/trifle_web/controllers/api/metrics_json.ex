defmodule TrifleWeb.Api.MetricsJSON do
  def create() do
    %{data: :ok}
  end

  def render("created.json", _assigns) do
    %{data: %{created: :ok}}
  end

  def render("index.json", assigns) do
    %{data: []}
  end
end
