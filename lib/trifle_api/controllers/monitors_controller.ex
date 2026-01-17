defmodule TrifleApi.MonitorsController do
  use TrifleApi, :controller

  alias Ecto.Multi
  alias Ecto.NoResultsError
  alias Trifle.Monitors
  alias Trifle.Monitors.Monitor
  alias Trifle.Repo
  alias TrifleApi.AuthContext

  plug(TrifleApi.Plugs.AuthenticateBySourceToken, %{mode: :any})

  def index(conn, _params) do
    with {:ok, %{user: user, membership: membership}} <- AuthContext.resolve_membership(conn) do
      monitors = Monitors.list_monitors_for_membership(user, membership)
      render(conn, "index.json", monitors: monitors)
    else
      _ -> render_unauthorized(conn)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, %{membership: membership}} <- AuthContext.resolve_membership(conn),
         {:ok, monitor} <- fetch_monitor(membership, id) do
      render(conn, "show.json", monitor: monitor)
    else
      {:error, :not_found} -> render_not_found(conn)
      {:error, :forbidden} -> render_forbidden(conn)
      _ -> render_unauthorized(conn)
    end
  end

  def create(conn, params) do
    with {:ok, %{user: user, membership: membership}} <- AuthContext.resolve_membership(conn),
         {:ok, attrs, alerts} <- monitor_attrs(params),
         {:ok, monitor} <- create_monitor_with_alerts(user, membership, attrs, alerts) do
      conn
      |> put_status(:created)
      |> render("show.json", monitor: monitor)
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset(conn, changeset)

      {:error, :forbidden} ->
        render_forbidden(conn)

      {:error, :invalid_alert} ->
        render_error(conn, :unprocessable_entity, "Invalid alert payload")

      {:error, :unauthorized} ->
        render_unauthorized(conn)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, inspect(reason))

      _ ->
        render_unauthorized(conn)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, %{membership: membership}} <- AuthContext.resolve_membership(conn),
         {:ok, monitor} <- fetch_monitor(membership, id),
         {:ok, attrs, alerts} <- monitor_attrs(params),
         {:ok, updated} <- update_monitor_with_alerts(monitor, membership, attrs, alerts) do
      render(conn, "show.json", monitor: updated)
    else
      {:error, :not_found} ->
        render_not_found(conn)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset(conn, changeset)

      {:error, :forbidden} ->
        render_forbidden(conn)

      {:error, :invalid_alert} ->
        render_error(conn, :unprocessable_entity, "Invalid alert payload")

      {:error, :unauthorized} ->
        render_unauthorized(conn)

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, inspect(reason))

      _ ->
        render_unauthorized(conn)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, %{membership: membership}} <- AuthContext.resolve_membership(conn),
         {:ok, monitor} <- fetch_monitor(membership, id),
         {:ok, %Monitor{} = deleted} <-
           Monitors.delete_monitor_for_membership(monitor, membership) do
      render(conn, "show.json", monitor: deleted)
    else
      {:error, :not_found} -> render_not_found(conn)
      {:error, %Ecto.Changeset{} = changeset} -> render_changeset(conn, changeset)
      {:error, :forbidden} -> render_forbidden(conn)
      _ -> render_unauthorized(conn)
    end
  end

  defp fetch_monitor(membership, id) do
    try do
      {:ok, Monitors.get_monitor_for_membership!(membership, id, preload: [:dashboard])}
    rescue
      NoResultsError -> {:error, :not_found}
    end
  end

  defp monitor_attrs(params) do
    payload = Map.get(params, "monitor") || params
    alerts = Map.get(payload, "alerts") || Map.get(payload, :alerts)

    attrs =
      payload
      |> Map.drop(["alerts", :alerts])

    {:ok, attrs, normalize_alerts(alerts)}
  end

  defp normalize_alerts(nil), do: nil
  defp normalize_alerts(alerts) when is_list(alerts), do: alerts
  defp normalize_alerts(_), do: nil

  defp create_monitor_with_alerts(user, membership, attrs, alerts) do
    multi =
      Multi.new()
      |> Multi.run(:monitor, fn _repo, _changes ->
        Monitors.create_monitor_for_membership(user, membership, attrs)
      end)
      |> Multi.run(:alerts, fn _repo, %{monitor: monitor} ->
        apply_alerts(monitor, membership, alerts)
      end)

    case Repo.transaction(multi) do
      {:ok, %{monitor: monitor}} ->
        {:ok, Monitors.get_monitor!(monitor.id, preload: [:dashboard])}

      {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp update_monitor_with_alerts(monitor, membership, attrs, alerts) do
    multi =
      Multi.new()
      |> Multi.run(:monitor, fn _repo, _changes ->
        Monitors.update_monitor_for_membership(monitor, membership, attrs)
      end)
      |> Multi.run(:alerts, fn _repo, %{monitor: updated} ->
        apply_alerts(updated, membership, alerts)
      end)

    case Repo.transaction(multi) do
      {:ok, %{monitor: updated}} ->
        {:ok, Monitors.get_monitor!(updated.id, preload: [:dashboard])}

      {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp apply_alerts(_monitor, _membership, nil), do: {:ok, []}

  defp apply_alerts(monitor, membership, alerts) when is_list(alerts) do
    existing = Monitors.list_alerts(monitor)
    existing_by_id = Map.new(existing, &{&1.id, &1})

    payload_ids =
      alerts
      |> Enum.map(fn alert ->
        Map.get(alert, "id") || Map.get(alert, :id)
      end)
      |> Enum.reject(&is_nil/1)

    result =
      Enum.reduce_while(alerts, {:ok, []}, fn alert, {:ok, acc} ->
        case upsert_alert(monitor, membership, existing_by_id, alert) do
          {:ok, updated} -> {:cont, {:ok, [updated | acc]}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    with {:ok, updated_alerts} <- result,
         {:ok, _deleted} <- delete_missing_alerts(monitor, membership, existing, payload_ids) do
      {:ok, Enum.reverse(updated_alerts)}
    end
  end

  defp apply_alerts(_monitor, _membership, _alerts), do: {:ok, []}

  defp upsert_alert(monitor, membership, existing_by_id, alert) when is_map(alert) do
    alert_id = Map.get(alert, "id") || Map.get(alert, :id)

    case Map.get(existing_by_id, alert_id) do
      nil ->
        Monitors.create_alert(monitor, membership, alert)

      existing ->
        Monitors.update_alert(monitor, membership, existing, alert)
    end
  end

  defp upsert_alert(_monitor, _membership, _existing, _alert),
    do: {:error, :invalid_alert}

  defp delete_missing_alerts(monitor, membership, existing, keep_ids) do
    existing
    |> Enum.reject(fn alert -> alert.id in keep_ids end)
    |> Enum.reduce_while({:ok, []}, fn alert, {:ok, acc} ->
      case Monitors.delete_alert(monitor, membership, alert) do
        {:ok, deleted} -> {:cont, {:ok, [deleted | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
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

  defp render_unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> put_view(TrifleApi.ErrorJSON)
    |> render("401.json")
  end

  defp render_forbidden(conn) do
    conn
    |> put_status(:forbidden)
    |> put_view(TrifleApi.ErrorJSON)
    |> render("403.json")
  end

  defp render_error(conn, status, detail) do
    conn
    |> put_status(status)
    |> json(%{errors: %{detail: detail}})
  end
end
