defmodule TrifleApp.ChatPageContext do
  @moduledoc """
  Normalized page context payloads for the persistent chat shell.
  """

  alias Trifle.Stats.Source
  alias TrifleApp.TimeframeParsing

  @type context :: %{
          required(:page_type) => atom(),
          required(:entity) => map(),
          required(:query) => map(),
          optional(:query_origin) => map(),
          optional(:capabilities) => map(),
          optional(:editable_payload_ref) => map(),
          required(:summary) => String.t()
        }

  @spec build(atom(), keyword()) :: context()
  def build(page_type, opts) when is_atom(page_type) and is_list(opts) do
    entity = Keyword.get(opts, :entity, %{}) |> stringify_keys()
    query = Keyword.get(opts, :query, %{}) |> normalize_query()
    query_origin = Keyword.get(opts, :query_origin, %{}) |> stringify_keys()
    capabilities = Keyword.get(opts, :capabilities, %{}) |> stringify_keys()

    editable_payload_ref =
      Keyword.get(opts, :editable_payload_ref, nil) |> normalize_optional_map()

    context = %{
      page_type: page_type,
      entity: entity,
      query: query,
      query_origin: query_origin,
      capabilities: capabilities,
      editable_payload_ref: editable_payload_ref,
      summary: Keyword.get(opts, :summary) || summary(page_type, entity, query)
    }

    Map.reject(context, fn {_key, value} -> value in [nil, %{}] end)
  end

  @spec timeframe(term(), term(), term(), term()) :: map()
  def timeframe(value, from, to, use_fixed_display) do
    %{
      value: blank_to_nil(value),
      from: iso8601(from),
      to: iso8601(to),
      display: format_display(from, to),
      use_fixed_display: use_fixed_display == true
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  @spec source_ref(Source.t() | nil) :: map() | nil
  def source_ref(%Source{} = source) do
    %{
      type: Source.type(source) |> Atom.to_string(),
      id: Source.id(source) |> to_string(),
      display_name: Source.display_name(source)
    }
  end

  def source_ref(_), do: nil

  @spec fingerprint(context() | nil) :: String.t() | nil
  def fingerprint(nil), do: nil

  def fingerprint(%{} = context) do
    query = Map.get(context, :query, Map.get(context, "query", %{}))
    source = Map.get(query, :source_ref, Map.get(query, "source_ref", %{}))
    timeframe = Map.get(query, :timeframe, Map.get(query, "timeframe", %{}))
    entity = Map.get(context, :entity, Map.get(context, "entity", %{}))

    payload =
      [
        Map.get(context, :page_type, Map.get(context, "page_type")),
        Map.get(entity, :id, Map.get(entity, "id")),
        Map.get(source, :type, Map.get(source, "type")),
        Map.get(source, :id, Map.get(source, "id")),
        Map.get(timeframe, :value, Map.get(timeframe, "value")),
        Map.get(timeframe, :from, Map.get(timeframe, "from")),
        Map.get(timeframe, :to, Map.get(timeframe, "to")),
        Map.get(query, :granularity, Map.get(query, "granularity")),
        Map.get(query, :metrics_key, Map.get(query, "metrics_key"))
      ]
      |> Enum.map(&to_string(&1 || ""))
      |> Enum.join("|")

    :sha256
    |> :crypto.hash(payload)
    |> Base.encode16(case: :lower)
  end

  @spec system_message(context()) :: String.t()
  def system_message(%{} = context) do
    fingerprint = fingerprint(context)
    query = Map.get(context, :query, Map.get(context, "query", %{}))
    source = Map.get(query, :source_ref, Map.get(query, "source_ref", %{}))
    timeframe = Map.get(query, :timeframe, Map.get(query, "timeframe", %{}))

    [
      "[page_context fingerprint=#{fingerprint}]",
      "page_type=#{Map.get(context, :page_type, Map.get(context, "page_type"))}",
      "entity_id=#{map_value(context, [:entity, :id]) || ""}",
      "entity_title=#{map_value(context, [:entity, :title]) || ""}",
      "source=#{Map.get(source, :display_name, Map.get(source, "display_name")) || ""}",
      "source_ref=#{source_ref_label(source)}",
      "timeframe=#{Map.get(timeframe, :value, Map.get(timeframe, "value")) || ""}",
      "timeframe_from=#{Map.get(timeframe, :from, Map.get(timeframe, "from")) || ""}",
      "timeframe_to=#{Map.get(timeframe, :to, Map.get(timeframe, "to")) || ""}",
      "timeframe_display=#{Map.get(timeframe, :display, Map.get(timeframe, "display")) || ""}",
      "granularity=#{Map.get(query, :granularity, Map.get(query, "granularity")) || ""}",
      "metrics_key=#{Map.get(query, :metrics_key, Map.get(query, "metrics_key")) || ""}",
      "summary=#{Map.get(context, :summary, Map.get(context, "summary")) || ""}"
    ]
    |> Enum.join("\n")
  end

  @spec cleared_system_message() :: String.t()
  def cleared_system_message do
    [
      "[page_context fingerprint=none]",
      "page_type=",
      "entity_id=",
      "entity_title=",
      "source=",
      "source_ref=",
      "timeframe=",
      "timeframe_from=",
      "timeframe_to=",
      "timeframe_display=",
      "granularity=",
      "metrics_key=",
      "summary=No current page context available"
    ]
    |> Enum.join("\n")
  end

  @spec extract_fingerprint(String.t() | nil) :: String.t() | nil
  def extract_fingerprint(nil), do: nil

  def extract_fingerprint(content) when is_binary(content) do
    case Regex.run(~r/\[page_context fingerprint=([0-9a-z-]+)\]/, content) do
      [_, fingerprint] -> fingerprint
      _ -> nil
    end
  end

  @spec summary_line(context() | nil) :: String.t() | nil
  def summary_line(nil), do: nil
  def summary_line(%{} = context), do: Map.get(context, :summary, Map.get(context, "summary"))

  defp normalize_query(query) do
    query
    |> stringify_keys()
    |> Map.update("source_ref", nil, &normalize_optional_map/1)
    |> Map.update("timeframe", %{}, &normalize_optional_map/1)
    |> Map.update("granularity", nil, &blank_to_nil/1)
    |> Map.update("metrics_key", nil, &blank_to_nil/1)
    |> Map.reject(fn {_key, value} -> value in [nil, %{}] end)
  end

  defp normalize_optional_map(nil), do: nil
  defp normalize_optional_map(%{} = value), do: stringify_keys(value)
  defp normalize_optional_map(_), do: nil

  defp stringify_keys(%{} = map) do
    map
    |> Enum.map(fn {key, value} ->
      {to_string(key), normalize_value(value)}
    end)
    |> Enum.into(%{})
  end

  defp stringify_keys(other), do: other

  defp normalize_value(%{} = value), do: stringify_keys(value)
  defp normalize_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_value(value), do: value

  defp blank_to_nil(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp blank_to_nil(value), do: value

  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp iso8601(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp iso8601(_), do: nil

  defp format_display(%DateTime{} = from, %DateTime{} = to) do
    TimeframeParsing.format_timeframe_display(from, to)
  rescue
    _ -> nil
  end

  defp format_display(_, _), do: nil

  defp source_ref_label(%{} = source) do
    type = Map.get(source, :type, Map.get(source, "type"))
    id = Map.get(source, :id, Map.get(source, "id"))

    if type && id do
      "#{type}:#{id}"
    end
  end

  defp source_ref_label(_), do: nil

  defp map_value(context, [root_key, leaf_key]) do
    root = Map.get(context, root_key, Map.get(context, to_string(root_key), %{}))
    Map.get(root, leaf_key, Map.get(root, to_string(leaf_key)))
  end

  defp summary(page_type, entity, query) do
    label =
      entity["title"] ||
        entity["name"] ||
        entity["id"] ||
        page_type

    pieces =
      [
        to_string(label),
        query["source_ref"] && query["source_ref"]["display_name"],
        query["timeframe"] && query["timeframe"]["value"],
        query["granularity"] && "granularity #{query["granularity"]}",
        query["metrics_key"] && "metrics key #{query["metrics_key"]}"
      ]
      |> Enum.reject(&(&1 in [nil, ""]))

    Enum.join(pieces, " · ")
  end
end
