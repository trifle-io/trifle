defmodule TrifleApi.TranspondersController do
  use TrifleApi, :controller

  alias Ecto.NoResultsError
  alias Trifle.Organizations
  alias Trifle.Organizations.Transponder
  alias Trifle.Stats.Source

  plug(TrifleApi.Plugs.AuthenticateBySourceToken, %{mode: :any})

  def index(%{assigns: %{current_source: %Source{} = source}} = conn, _params) do
    render(conn, "index.json", transponders: list_transponders(source))
  end

  def create(%{assigns: %{current_source: %Source{} = source}} = conn, params) do
    with {:ok, attrs} <- transponder_attrs(params) do
      attrs = put_next_order(attrs, source)

      case create_transponder(source, attrs) do
        {:ok, %Transponder{} = transponder} ->
          conn
          |> put_status(:created)
          |> render("show.json", transponder: transponder)

        {:error, %Ecto.Changeset{} = changeset} ->
          render_changeset(conn, changeset)
      end
    else
      {:error, :invalid_params} ->
        render_error(conn, :unprocessable_entity, "Invalid request parameters")
    end
  end

  def update(%{assigns: %{current_source: %Source{} = source}} = conn, %{"id" => id} = params) do
    with {:ok, %Transponder{} = transponder} <- fetch_transponder(source, id),
         {:ok, attrs} <- transponder_attrs(params),
         {:ok, %Transponder{} = updated} <- Organizations.update_transponder(transponder, attrs) do
      render(conn, "show.json", transponder: updated)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> put_view(TrifleApi.ErrorJSON)
        |> render("404.json")

      {:error, :invalid_params} ->
        render_error(conn, :unprocessable_entity, "Invalid request parameters")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset(conn, changeset)
    end
  end

  def delete(%{assigns: %{current_source: %Source{} = source}} = conn, %{"id" => id}) do
    with {:ok, %Transponder{} = transponder} <- fetch_transponder(source, id),
         {:ok, %Transponder{} = deleted} <- Organizations.delete_transponder(transponder) do
      render(conn, "show.json", transponder: deleted)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> put_view(TrifleApi.ErrorJSON)
        |> render("404.json")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset(conn, changeset)
    end
  end

  defp list_transponders(%Source{} = source) do
    record = Source.record(source)

    case Source.type(source) do
      :database -> Organizations.list_transponders_for_database(record)
      :project -> Organizations.list_transponders_for_project(record)
    end
  end

  defp create_transponder(%Source{} = source, attrs) do
    record = Source.record(source)

    case Source.type(source) do
      :database -> Organizations.create_transponder_for_database(record, attrs)
      :project -> Organizations.create_transponder_for_project(record, attrs)
    end
  end

  defp fetch_transponder(%Source{} = source, id) do
    record = Source.record(source)

    try do
      {:ok, Organizations.get_transponder_for_source!(record, id)}
    rescue
      NoResultsError -> {:error, :not_found}
    end
  end

  defp put_next_order(attrs, %Source{} = source) do
    if Map.has_key?(attrs, "order") do
      attrs
    else
      record = Source.record(source)
      Map.put(attrs, "order", Organizations.get_next_transponder_order(record))
    end
  end

  defp transponder_attrs(params) do
    payload = Map.get(params, "transponder") || params

    with {:ok, config} <- normalize_config(payload),
         {:ok, enabled} <- normalize_enabled(Map.get(payload, "enabled")),
         {:ok, order} <- normalize_order(Map.get(payload, "order")) do
      attrs =
        %{}
        |> maybe_put("name", Map.get(payload, "name"))
        |> maybe_put("key", Map.get(payload, "key"))
        |> maybe_put("config", config)
        |> maybe_put("enabled", enabled)
        |> maybe_put("order", order)

      {:ok, attrs}
    end
  end

  defp normalize_config(payload) do
    case Map.get(payload, "config") do
      %{} = config ->
        {:ok, config}

      nil ->
        derived =
          payload
          |> Map.take(["paths", "expression", "response"])
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Enum.into(%{})

        if map_size(derived) == 0, do: {:ok, nil}, else: {:ok, derived}

      _ ->
        {:error, :invalid_params}
    end
  end

  defp normalize_enabled(nil), do: {:ok, nil}
  defp normalize_enabled(value) when is_boolean(value), do: {:ok, value}

  defp normalize_enabled(value) when is_binary(value) do
    case String.trim(value) do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> {:error, :invalid_params}
    end
  end

  defp normalize_enabled(_), do: {:error, :invalid_params}

  defp normalize_order(nil), do: {:ok, nil}
  defp normalize_order(value) when is_integer(value), do: {:ok, value}

  defp normalize_order(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_params}
    end
  end

  defp normalize_order(_), do: {:error, :invalid_params}

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)

  defp render_changeset(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(TrifleApp.ChangesetJSON)
    |> render("error.json", changeset: changeset)
  end

  defp render_error(conn, status, detail) do
    conn
    |> put_status(status)
    |> json(%{errors: %{detail: detail}})
  end
end
