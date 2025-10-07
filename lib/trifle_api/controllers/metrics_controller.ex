defmodule TrifleApi.MetricsController do
  use TrifleApi, :controller

  plug(TrifleApi.Plugs.AuthenticateByProjectToken, %{mode: :read} when action in [:index])
  plug(TrifleApi.Plugs.AuthenticateByProjectToken, %{mode: :write} when action in [:create])

  def index(%{assigns: %{current_project: current_project}} = conn, params) do
    conn
    |> render("index.json")
  end

  def create(
        %{assigns: %{current_project: current_project}} = conn,
        %{"key" => key, "at" => at, "values" => values} = params
      ) do
    with key when is_binary(key) and byte_size(key) > 0 <- params["key"],
         at when is_binary(at) and byte_size(at) > 0 <- params["at"],
         values when not is_nil(values) <- params["values"],
         {:ok, at, _} <- DateTime.from_iso8601(at),
         stats <-
           Trifle.Stats.track(
             key,
             at,
             values,
             Trifle.Organizations.Project.stats_config(current_project)
           ) do
      conn
      |> put_status(:created)
      |> render("created.json")
    else
      nil ->
        conn
        |> put_status(:bad_request)
        |> render("400.json")

      "" ->
        conn
        |> put_status(:bad_request)
        |> render("400.json")

      {:error, :invalid_format} ->
        conn
        |> put_status(:bad_request)
        |> render("400.json")
    end
  end

  def create(conn, params) do
    conn
    |> put_status(:bad_request)
    |> render("400.json")
  end

  def health(conn, _params) do
    conn
    |> put_status(:ok)
    |> render("health.json")
  end
end
