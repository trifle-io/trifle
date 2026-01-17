defmodule TrifleApi.DashboardsController do
  use TrifleApi, :controller

  alias Ecto.NoResultsError
  alias Trifle.Organizations
  alias Trifle.Organizations.Dashboard
  alias TrifleApi.AuthContext

  plug(TrifleApi.Plugs.AuthenticateBySourceToken, %{mode: :any})

  def index(conn, _params) do
    with {:ok, %{user: user, membership: membership}} <- AuthContext.resolve_membership(conn) do
      dashboards =
        user
        |> Organizations.list_all_dashboards_for_membership(membership)
        |> Enum.filter(&visible_to_org?/1)

      render(conn, "index.json", dashboards: dashboards)
    else
      _ -> render_unauthorized(conn)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, %{membership: membership}} <- AuthContext.resolve_membership(conn),
         {:ok, dashboard} <- fetch_dashboard(membership, id),
         :ok <- ensure_visible(dashboard) do
      render(conn, "show.json", dashboard: dashboard)
    else
      {:error, :not_found} -> render_not_found(conn)
      {:error, :forbidden} -> render_not_found(conn)
      _ -> render_unauthorized(conn)
    end
  end

  def create(conn, params) do
    with {:ok, %{user: user, membership: membership}} <- AuthContext.resolve_membership(conn),
         {:ok, attrs} <- dashboard_attrs(params, :create),
         {:ok, %Dashboard{} = dashboard} <-
           Organizations.create_dashboard_for_membership(user, membership, attrs) do
      conn
      |> put_status(:created)
      |> render("show.json", dashboard: dashboard)
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset(conn, changeset)

      _ ->
        render_unauthorized(conn)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, %{membership: membership}} <- AuthContext.resolve_membership(conn),
         {:ok, dashboard} <- fetch_dashboard(membership, id),
         :ok <- ensure_visible(dashboard),
         {:ok, attrs} <- dashboard_attrs(params, :update),
         {:ok, %Dashboard{} = updated} <-
           Organizations.update_dashboard_for_membership(dashboard, membership, attrs) do
      render(conn, "show.json", dashboard: updated)
    else
      {:error, :not_found} -> render_not_found(conn)
      {:error, :forbidden} -> render_not_found(conn)
      {:error, :unauthorized} -> render_forbidden(conn)
      {:error, %Ecto.Changeset{} = changeset} -> render_changeset(conn, changeset)
      _ -> render_unauthorized(conn)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, %{membership: membership}} <- AuthContext.resolve_membership(conn),
         {:ok, dashboard} <- fetch_dashboard(membership, id),
         :ok <- ensure_visible(dashboard),
         {:ok, %Dashboard{} = deleted} <-
           Organizations.delete_dashboard_for_membership(dashboard, membership) do
      render(conn, "show.json", dashboard: deleted)
    else
      {:error, :not_found} -> render_not_found(conn)
      {:error, :forbidden} -> render_not_found(conn)
      {:error, :unauthorized} -> render_forbidden(conn)
      {:error, %Ecto.Changeset{} = changeset} -> render_changeset(conn, changeset)
      _ -> render_unauthorized(conn)
    end
  end

  defp fetch_dashboard(%{organization_id: _org_id} = membership, id) do
    try do
      {:ok, Organizations.get_dashboard_for_membership!(membership, id)}
    rescue
      NoResultsError -> {:error, :not_found}
    end
  end

  defp visible_to_org?(%Dashboard{} = dashboard), do: dashboard.visibility == true
  defp visible_to_org?(_), do: false

  defp ensure_visible(%Dashboard{} = dashboard) do
    if visible_to_org?(dashboard), do: :ok, else: {:error, :forbidden}
  end

  defp dashboard_attrs(params, action) do
    payload = Map.get(params, "dashboard") || params

    attrs =
      payload
      |> Map.take([
        "name",
        "key",
        "visibility",
        "locked",
        "payload",
        "segments",
        "group_id",
        "default_timeframe",
        "default_granularity",
        "source_type",
        "source_id",
        "database_id",
        "position",
        "source"
      ])

    attrs =
      if action == :create and not Map.has_key?(attrs, "visibility") and
           not Map.has_key?(attrs, :visibility) do
        Map.put(attrs, "visibility", true)
      else
        attrs
      end

    {:ok, attrs}
  end

  defp render_changeset(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(TrifleApp.ChangesetJSON)
    |> render("error.json", changeset: changeset)
  end

  defp render_not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(TrifleApi.ErrorJSON)
    |> render("404.json")
  end

  defp render_forbidden(conn) do
    conn
    |> put_status(:forbidden)
    |> put_view(TrifleApi.ErrorJSON)
    |> render("403.json")
  end

  defp render_unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> put_view(TrifleApi.ErrorJSON)
    |> render("401.json")
  end
end
