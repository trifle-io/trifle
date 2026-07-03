defmodule TrifleApp.ExportFilename do
  @moduledoc """
  Builds sanitized, UTC-timestamped filenames for exports (CSV/JSON/PDF/PNG).

  Callers supply the context-specific name parts (dashboard name, source
  name, monitor name, ...); nil parts are dropped.
  """

  def build(prefix, parts, ext) do
    ts = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(:basic)

    base =
      [prefix | List.wrap(parts)]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&sanitize_component/1)
      |> Enum.join("-")

    if(base == "", do: prefix, else: base) <> "-" <> ts <> ext
  end

  defp sanitize_component(value) do
    value
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_-]+/, "-")
  end
end
