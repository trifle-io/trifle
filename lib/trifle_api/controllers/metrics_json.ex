defmodule TrifleApi.MetricsJSON do
  def create() do
    %{data: :ok}
  end

  def render("created.json", _assigns) do
    %{data: %{created: :ok}}
  end

  def render("index.json", %{series: series}) do
    %{data: format_series(series)}
  end

  def render("index.json", _assigns) do
    %{data: format_series(%{})}
  end

  def render("400.json", _assigns) do
    %{errors: %{detail: "Bad request"}}
  end

  def render("500.json", _assigns) do
    %{errors: %{detail: "Internal server error"}}
  end

  def render("health.json", _assigns) do
    %{status: "ok", timestamp: DateTime.utc_now()}
  end

  defp format_series(series) when is_map(series) do
    %{
      at: format_timestamps(Map.get(series, :at, [])),
      values: Map.get(series, :values, [])
    }
  end

  defp format_series(_series) do
    %{at: [], values: []}
  end

  defp format_timestamps(list) when is_list(list) do
    Enum.map(list, &format_timestamp/1)
  end

  defp format_timestamps(_), do: []

  defp format_timestamp(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_timestamp(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  defp format_timestamp(value), do: value
end
