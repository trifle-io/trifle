defmodule TrifleApi.MetricsQueryJSON do
  def render("show.json", %{payload: payload}) do
    %{data: payload}
  end

  def render("error.json", %{error: error}) do
    %{errors: error}
  end
end
