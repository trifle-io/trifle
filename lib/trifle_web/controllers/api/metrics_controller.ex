defmodule TrifleWeb.Api.MetricsController do
  use TrifleWeb, :controller

  plug(TrifleWeb.Plugs.AuthenticateByProjectToken, %{mode: :read} when action in [:index])
  plug(TrifleWeb.Plugs.AuthenticateByProjectToken, %{mode: :write} when action in [:create])

  require IEx

  def create(%{assigns: %{current_project: current_project}} = conn, params) do
    # IEx.pry
    conn
    |> put_status(:created)
    |> render("created.json")
  end

  def index(%{assigns: %{current_project: current_project}} = conn, params) do
      conn
    |> render("index.json")
  end

  # def create(
  #       %{assigns: %{current_user: current_user, current_project: current_project}} = conn,
  #       params
  #     ) do
  #   with project_id when not is_nil(project_id) <- params["project_id"],
  #        dimensions when not is_nil(dimensions) <- params["dimensions"],
  #        data when not is_nil(data) <- params["data"],
  #        method when not is_nil(method) <- params["method"],
  #        payload <- [project_id, dimensions, data, method],
  #        {:ok, _metric} <- Metric.create(payload, current_user, current_project) do
  #     conn
  #     |> put_status(:created)
  #     |> put_view(TrifleWeb.Api.MetricView)
  #     |> render("created.json", %{})
  #   else
  #     nil ->
  #       conn
  #       |> put_resp_content_type("application/json")
  #       |> put_status(:bad_request)
  #       |> put_view(TrifleWeb.Api.ErrorView)
  #       |> render("400.json", %{})

  #     {:error, :unauthorized} ->
  #       conn
  #       |> put_resp_content_type("application/json")
  #       |> put_status(:unauthorized)
  #       |> put_view(TrifleWeb.Api.ErrorView)
  #       |> render("401.json", %{})

  #     {:error, changeset} ->
  #       conn
  #       |> put_status(:unprocessable_entity)
  #       |> put_view(TrifleWeb.ChangesetView)
  #       |> render("error.json", changeset: changeset)
  #   end
  # end
end
