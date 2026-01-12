defmodule TrifleApi.TranspondersController do
  use TrifleApi, :controller

  alias Ecto.NoResultsError
  alias Trifle.Organizations
  alias Trifle.Organizations.Transponder
  alias Trifle.Stats.Source

  @expression_type "Trifle.Stats.Transponder.Expression"

  plug(TrifleApi.Plugs.AuthenticateBySourceToken, %{mode: :read} when action in [:index])

  plug(
    TrifleApi.Plugs.AuthenticateBySourceToken,
    %{mode: :write} when action in [:create, :update]
  )

  def index(%{assigns: %{current_source: %Source{} = source}} = conn, _params) do
    transponders =
      source
      |> list_transponders()
      |> Enum.filter(fn transponder -> expression_type?(transponder.type) end)

    render(conn, "index.json", transponders: transponders)
  end

  def create(%{assigns: %{current_source: %Source{} = source}} = conn, params) do
    with {:ok, attrs} <- transponder_attrs(params, :create) do
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
      {:error, :unsupported_type} ->
        render_error(conn, :unprocessable_entity, "Unsupported transponder type")

      {:error, :invalid_params} ->
        render_error(conn, :unprocessable_entity, "Invalid request parameters")
    end
  end

  def update(%{assigns: %{current_source: %Source{} = source}} = conn, %{"id" => id} = params) do
    with {:ok, %Transponder{} = transponder} <- fetch_transponder(source, id),
         :ok <- ensure_expression_transponder(transponder),
         {:ok, attrs} <- transponder_attrs(params, :update),
         {:ok, %Transponder{} = updated} <- Organizations.update_transponder(transponder, attrs) do
      render(conn, "show.json", transponder: updated)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> put_view(TrifleApi.ErrorJSON)
        |> render("404.json")

      {:error, :unsupported_type} ->
        render_error(conn, :unprocessable_entity, "Unsupported transponder type")

      {:error, :invalid_params} ->
        render_error(conn, :unprocessable_entity, "Invalid request parameters")

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

  defp ensure_expression_transponder(%Transponder{type: type}) do
    if expression_type?(type), do: :ok, else: {:error, :unsupported_type}
  end

  defp transponder_attrs(params, action) do
    payload = Map.get(params, "transponder") || params

    with {:ok, type} <- normalize_type(Map.get(payload, "type"), action),
         {:ok, config} <- normalize_config(payload),
         {:ok, enabled} <- normalize_enabled(Map.get(payload, "enabled")),
         {:ok, order} <- normalize_order(Map.get(payload, "order")) do
      attrs =
        %{}
        |> maybe_put("name", Map.get(payload, "name"))
        |> maybe_put("key", Map.get(payload, "key"))
        |> maybe_put("type", type)
        |> maybe_put("config", config)
        |> maybe_put("enabled", enabled)
        |> maybe_put("order", order)

      {:ok, attrs}
    end
  end

  defp normalize_type(nil, :create), do: {:ok, @expression_type}
  defp normalize_type(nil, :update), do: {:ok, nil}

  defp normalize_type(type, action) when is_binary(type) do
    trimmed = String.trim(type)

    cond do
      trimmed == "" and action == :create ->
        {:ok, @expression_type}

      trimmed == "" and action == :update ->
        {:ok, nil}

      expression_type?(trimmed) ->
        {:ok, @expression_type}

      String.downcase(trimmed) == "expression" ->
        {:ok, @expression_type}

      true ->
        {:error, :unsupported_type}
    end
  end

  defp normalize_type(_type, _action), do: {:error, :invalid_params}

  defp normalize_config(payload) do
    case Map.get(payload, "config") do
      %{} = config ->
        {:ok, config}

      nil ->
        derived =
          payload
          |> Map.take(["paths", "expression", "response_path"])
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

  defp expression_type?(type) when is_binary(type) do
    String.downcase(type) == String.downcase(@expression_type)
  end

  defp expression_type?(_), do: false

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
