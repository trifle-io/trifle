defmodule TrifleApi.MetricsJSON do
  def create() do
    %{data: :ok}
  end

  def render("created.json", _assigns) do
    %{data: %{created: :ok}}
  end

  def render("index.json", _assigns) do
    %{data: []}
  end

  def render("400.json", _assigns) do
    %{errors: %{detail: "Bad request"}}
  end

  def render("health.json", _assigns) do
    %{status: "ok", timestamp: DateTime.utc_now()}
  end
end
