defmodule TrifleApp.Exporters.ExportLog do
  @moduledoc false

  @masked_segment_length 4

  def normalize(nil), do: %{}

  def normalize(%{} = context), do: context

  def normalize(context) when is_list(context), do: Enum.into(context, %{})

  def normalize(context), do: %{value: inspect(context)}

  def merge(existing, extras) do
    existing
    |> normalize()
    |> Map.merge(normalize(extras))
  end

  def ensure_ref(context) do
    Map.put_new(context, :export_ref, generate_ref())
  end

  def ensure_format(context, format) do
    Map.put_new(context, :format, format)
  end

  def ensure_layout(context, layout) do
    context
    |> maybe_put(:layout_id, layout.id)
    |> maybe_put(:layout_kind, layout.kind)
    |> maybe_put(:layout_title, layout.title)
  end

  def label(context) do
    context
    |> normalize()
    |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
    |> Enum.map(fn {k, v} -> "#{k}=#{format_value(v)}" end)
    |> Enum.join(" ")
  end

  def summarize_url(nil), do: "n/a"

  def summarize_url(url) when is_binary(url) do
    uri = URI.parse(url)
    path = sanitize_path(uri.path || "/")

    query_keys = decode_query_keys(uri.query)

    case query_keys do
      nil -> path
      [] -> path
      keys -> path <> " query_keys=" <> Enum.join(keys, ",")
    end
  end

  def monotonic_now_ms do
    System.monotonic_time(:millisecond)
  end

  def since_ms(start_ms) when is_integer(start_ms) do
    monotonic_now_ms() - start_ms
  end

  defp maybe_put(context, _key, nil), do: context
  defp maybe_put(context, _key, ""), do: context
  defp maybe_put(context, key, value), do: Map.put(context, key, value)

  defp format_value(value) when is_binary(value) and byte_size(value) <= 100, do: value

  defp format_value(value) when is_binary(value) do
    String.slice(value, 0, 97) <> "..."
  end

  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value) when is_integer(value), do: Integer.to_string(value)

  defp format_value(value) when is_float(value) do
    :erlang.float_to_binary(value, decimals: 2)
  end

  defp format_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_value(%Date{} = date), do: Date.to_iso8601(date)

  defp format_value(value) when is_struct(value), do: inspect(value)
  defp format_value(value) when is_map(value), do: inspect(value)
  defp format_value(value) when is_list(value), do: inspect(value)
  defp format_value(value), do: inspect(value)

  defp sanitize_path(path) when path in [nil, ""], do: "/"

  defp sanitize_path(path) do
    segments =
      path
      |> String.split("/", trim: true)
      |> Enum.map(&mask_if_token/1)

    "/" <> Enum.join(segments, "/")
  end

  defp mask_if_token(segment) when byte_size(segment) < 16, do: segment

  defp mask_if_token(segment) do
    prefix = String.slice(segment, 0, @masked_segment_length)
    suffix = String.slice(segment, -@masked_segment_length, @masked_segment_length)
    prefix <> "..." <> suffix
  end

  defp decode_query_keys(nil), do: nil
  defp decode_query_keys(""), do: nil

  defp decode_query_keys(query) when is_binary(query) do
    try do
      query
      |> URI.decode_query()
      |> Map.keys()
    rescue
      _ -> nil
    end
  end

  defp decode_query_keys(_), do: nil

  defp generate_ref do
    "exp-" <> Base.encode32(:crypto.strong_rand_bytes(5), case: :lower)
  end
end
