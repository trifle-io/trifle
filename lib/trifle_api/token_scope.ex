defmodule TrifleApi.TokenScope do
  @moduledoc """
  Keeps API tokens inside the sources they were granted.

  Source-scoped endpoints authenticate against the source named in the
  `X-Trifle-Source-Id` header, but dashboards and monitors are organization-wide
  objects that each point at a source of their own. These helpers apply the
  token's grants to those objects, so a token for one source cannot read or change
  objects that belong to another (a wildcard grant covers every source).
  """

  alias Trifle.Organizations
  alias Trifle.Organizations.OrganizationApiToken
  alias Trifle.Stats.Source

  @type mode :: :read | :write

  @doc "Whether the request's token has `mode` access to the given source."
  def permits?(conn, source_type, source_id, mode) when mode in [:read, :write] do
    case conn.assigns[:current_api_token] do
      %OrganizationApiToken{permissions: permissions} ->
        Organizations.token_has_permission?(permissions, source_type, source_id, mode)

      _ ->
        false
    end
  end

  @doc """
  Whether the token may access a stored object (dashboard, monitor). An object
  without a source is only reachable with a wildcard grant.
  """
  def permits_record?(conn, record, mode) when is_map(record) do
    permits?(conn, Map.get(record, :source_type), Map.get(record, :source_id), mode)
  end

  @doc "Keeps only the records the token may access."
  def filter(conn, records, mode) when is_list(records) do
    Enum.filter(records, &permits_record?(conn, &1, mode))
  end

  @doc """
  Checks every source named in request attributes.

  A payload can name a source in more than one way (`source_id`, the legacy
  `database_id`, a nested `source` object), and the contexts that save it pick
  one of them by their own precedence. Rather than mirror that precedence here,
  all of them must be within the token's grants, so no combination can smuggle
  in a source the token has no access to.

  Returns `:ok` when the attributes name no source or only permitted ones,
  `{:error, :forbidden}` otherwise.
  """
  def authorize_attrs(conn, attrs, mode \\ :write) when is_map(attrs) do
    if Enum.all?(attrs_sources(attrs), &permits_reference?(conn, &1, mode)),
      do: :ok,
      else: {:error, :forbidden}
  end

  # An id given without a type may be either kind of source; ids are UUIDs, so
  # a grant for that id under either kind identifies the same source.
  defp permits_reference?(conn, {nil, id}, mode),
    do: permits?(conn, "database", id, mode) or permits?(conn, "project", id, mode)

  defp permits_reference?(conn, {type, id}, mode), do: permits?(conn, type, id, mode)

  @doc """
  For creates: if the attributes name no source at all, pin them to the source
  the request authenticated against instead of letting a default be picked.
  """
  def put_default_source(conn, attrs) when is_map(attrs) do
    case {attrs_sources(attrs), conn.assigns[:current_source]} do
      {[], %Source{} = source} ->
        attrs
        |> Map.put("source_type", source |> Source.type() |> to_string())
        |> Map.put("source_id", source |> Source.id() |> to_string())

      _ ->
        attrs
    end
  end

  # Every {type, id} the payload refers to, under string or atom keys. Only
  # references that carry an id can point anywhere; the type may be missing.
  defp attrs_sources(attrs) do
    nested = get(attrs, "source")

    [
      {get(attrs, "source_type"), get(attrs, "source_id")},
      {"database", get(attrs, "database_id")},
      if(is_map(nested), do: {get(nested, "type"), get(nested, "id")}, else: {nil, nil})
    ]
    |> Enum.filter(fn {_type, id} -> present?(id) end)
    |> Enum.map(fn
      {type, id} when type in [nil, ""] -> {nil, id}
      {type, id} -> {to_string(type), id}
    end)
    |> Enum.uniq()
  end

  defp get(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, String.to_existing_atom(key))
    end
  rescue
    ArgumentError -> nil
  end

  defp present?(value), do: is_binary(value) and value != ""
end
