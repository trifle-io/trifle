defmodule Trifle.Traces.Reader do
  @moduledoc "Organization-scoped, read-only access to trace indexes and payload stores."

  alias Trifle.Organizations
  alias Trifle.Organizations.Database
  alias Trifle.Stats.Source
  alias Trifle.Traces.Driver

  def sources(membership) do
    membership
    |> Source.list_for_membership()
    |> Enum.filter(fn source ->
      Source.type(source) == :database and Database.traces_configured?(source.record)
    end)
  end

  def source(%{organization_id: org_id}, id) when is_binary(id) do
    with {:ok, :database, database} <- Organizations.get_operational_source_for_org(org_id, id),
         true <- Database.traces_configured?(database) do
      {:ok, Source.from_database(database)}
    else
      _ -> {:error, :unavailable}
    end
  end

  def source(_, _), do: {:error, :unavailable}

  def search(membership, id, filters, opts \\ []) do
    read(membership, id, opts, fn config ->
      filters |> Keyword.put(:limit, 20) |> Keyword.put(:config, config) |> Trifle.Traces.search()
    end)
  end

  def detail(membership, id, reference, opts \\ []) do
    read(membership, id, opts, &find!(&1, reference))
  end

  def part(membership, id, reference, part, opts \\ []) do
    read(membership, id, opts, fn config ->
      record = find!(config, reference)
      entries = read_part!(config, record, part)
      Enum.with_index(entries, fn entry, row -> %{entry: entry, part: part, row: row} end)
    end)
  end

  # Scan only a bounded batch of parts; never read attachment bodies to list them.
  def attachments(membership, id, reference, after_part \\ 0, opts \\ []) do
    read(membership, id, opts, fn config ->
      record = find!(config, reference)

      unless is_integer(after_part) and after_part >= 0 and after_part <= record.parts,
        do: throw(:not_found)

      last_part = min(after_part + 10, record.parts)

      attachments =
        if after_part < last_part do
          Enum.flat_map((after_part + 1)..last_part, fn part ->
            config
            |> read_part!(record, part)
            |> Enum.with_index()
            |> Enum.flat_map(fn {entry, row} ->
              name = field(entry, :message)

              if to_string(field(entry, :type)) == "media" and safe_component?(name),
                do: [%{name: name, size: field(entry, :size), part: part, row: row}],
                else: []
            end)
          end)
        else
          []
        end

      %{attachments: attachments, next_part: if(last_part < record.parts, do: last_part)}
    end)
  end

  # A download is addressed by an entry, never by a caller-supplied object name.
  def artifact(membership, id, reference, part, row, opts \\ []) do
    read(membership, id, opts, fn config ->
      record = find!(config, reference)
      entries = read_part!(config, record, part)
      entry = if is_integer(row) and row >= 0, do: Enum.at(entries, row)

      unless is_map(entry) and to_string(field(entry, :type)) == "media",
        do: throw(:not_found)

      name = field(entry, :message)
      unless safe_component?(name), do: throw(:not_found)
      body = Trifle.Traces.read_artifact(record, name, config: config)
      unless is_binary(body), do: throw(:not_found)
      %{name: name, body: body}
    end)
  end

  def field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  def preview(%{name: name, body: body}) do
    if String.ends_with?(String.downcase(name), [".txt", ".log", ".json", ".csv"]) and
         String.valid?(body) do
      # Slice by characters so a multibyte character is never cut in half.
      %{text: String.slice(body, 0, 32_768), truncated: String.length(body) > 32_768}
    else
      %{text: nil, truncated: false}
    end
  end

  defp read(membership, id, opts, fun) do
    with {:ok, source} <- source(membership, id) do
      provider = Keyword.get(opts, :configuration, &Trifle.Traces.Source.Database.configuration/1)
      {:ok, fun.(provider.(source.record))}
    end
  rescue
    _ -> {:error, :storage_unavailable}
  catch
    :not_found -> {:error, :not_found}
    _, _ -> {:error, :storage_unavailable}
  end

  defp find!(config, reference) do
    unless is_binary(reference) and byte_size(reference) <= 1024, do: throw(:not_found)
    Trifle.Traces.find(reference, config: config) || throw(:not_found)
  end

  defp read_part!(config, record, part) do
    unless is_integer(part) and part >= 1 and part <= record.parts and
             safe_component?(record.reference) and safe_key?(record.key),
           do: throw(:not_found)

    Driver.call(config.data_driver, :read_part, [record, part])
  end

  defp safe_key?(key) when is_binary(key),
    do: Enum.all?(String.split(key, "/"), &safe_component?/1)

  defp safe_key?(_), do: false

  defp safe_component?(value) when is_binary(value) do
    value not in ["", ".", ".."] and not String.contains?(value, ["/", "\\", <<0>>])
  end

  defp safe_component?(_), do: false
end
