defmodule TrifleApi.MetricsQueryJSON do
  alias TrifleApi.NumberNormalizer

  def render("show.json", %{payload: payload}) do
    %{data: NumberNormalizer.normalize(payload)}
  end

  def render("error.json", %{error: error}) do
    %{errors: error}
  end
end
