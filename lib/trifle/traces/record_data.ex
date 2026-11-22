defmodule Trifle.Traces.RecordData do
  @moduledoc false

  def summary(record) do
    %{
      reference: record.reference,
      path: record.key,
      state: record.state,
      tags: record.tags,
      first_at: iso8601(record.first_at),
      last_at: iso8601(record.last_at),
      duration_ms: record.duration,
      entry_count: record.length,
      part_count: record.parts
    }
  end

  def metadata(record) do
    %{
      meta: json_value(record.meta),
      context: json_value(record.context),
      counters: record.counters,
      retention_days: record.retention,
      expires_at: iso8601(record.expires_at)
    }
  end

  defp iso8601(nil), do: nil
  defp iso8601(at), do: DateTime.to_iso8601(at)

  # The Mongo index can return native BSON values in context.
  defp json_value(%BSON.ObjectId{} = id), do: to_string(id)

  defp json_value(%_{} = value) do
    case Jason.encode(value) do
      {:ok, encoded} -> Jason.decode!(encoded)
      {:error, _} -> inspect(value)
    end
  end

  defp json_value(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, json_value(item)} end)

  defp json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)

  defp json_value(value) when is_binary(value),
    do: if(String.valid?(value), do: value, else: inspect(value))

  defp json_value(value), do: value
end
