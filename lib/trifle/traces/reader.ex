defmodule Trifle.Traces.Reader do
  @moduledoc "Organization-scoped, read-only access to trace indexes and payload stores."

  require Logger

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
    read(membership, id, :search, opts, fn config ->
      filters
      |> Keyword.put_new(:limit, 20)
      |> Keyword.put(:config, config)
      |> Trifle.Traces.search()
    end)
  end

  def detail(membership, id, reference, opts \\ []) do
    read(membership, id, :detail, opts, &find!(&1, reference))
  end

  def part(membership, id, reference, part, opts \\ []) do
    read(membership, id, :part, opts, fn config ->
      record = find!(config, reference)
      entries = read_part!(config, record, part)
      Enum.with_index(entries, fn entry, row -> %{entry: entry, part: part, row: row} end)
    end)
  end

  def contents(membership, id, reference, part, opts \\ []) do
    read(membership, id, :contents, opts, fn config ->
      record = find!(config, reference)

      entries =
        case {part, record.parts} do
          {nil, _} -> []
          {1, 0} -> []
          _ -> read_part!(config, record, part)
        end

      %{record: record, entries: entries}
    end)
  end

  # Scan only a bounded batch of parts; never read attachment bodies to list them.
  def attachments(membership, id, reference, after_part \\ 0, opts \\ []) do
    read(membership, id, :attachments, opts, fn config ->
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
              case attachment(entry, part, row) do
                nil -> []
                attachment -> [attachment]
              end
            end)
          end)
        else
          []
        end

      %{attachments: attachments, next_part: if(last_part < record.parts, do: last_part)}
    end)
  end

  def attachment(entry, part, row) do
    name = field(entry, :message)

    if to_string(field(entry, :type)) == "media" and safe_component?(name),
      do: %{name: name, size: field(entry, :size), part: part, row: row}
  end

  # A download is addressed by an entry, never by a caller-supplied object name.
  #
  # Returns a handle, not the body: the name, the size as stored (the `size` an
  # entry declares is written by the tenant and is not trusted), and a function
  # that reads an inclusive byte range. Nothing is read from the artifact here.
  def artifact(membership, id, reference, part, row, opts \\ []) do
    read(membership, id, :artifact, opts, fn config ->
      record = find!(config, reference)
      entries = read_part!(config, record, part)
      entry = if is_integer(row) and row >= 0, do: Enum.at(entries, row)

      descriptor = if is_map(entry), do: attachment(entry, part, row)
      %{name: name} = descriptor || throw(:not_found)

      size = Trifle.Traces.artifact_size(record, name, config: config)
      unless is_integer(size) and size >= 0, do: throw(:not_found)
      if size > setting(:max_artifact_bytes), do: throw(:too_large)

      %{
        name: name,
        size: size,
        source_id: id,
        read: &Trifle.Traces.read_artifact_range(record, name, &1, &2, config: config)
      }
    end)
  end

  @doc """
  Lazily reads bytes `first..last` of an artifact in fixed-size chunks, so a
  large file never sits in memory. Raises if storage fails part-way.
  """
  def stream(%{read: read}, first, last) do
    chunk = setting(:artifact_chunk_bytes)

    Stream.unfold(first, fn
      offset when offset > last ->
        nil

      offset ->
        stop = min(offset + chunk - 1, last)
        {read.(offset, stop), stop + 1}
    end)
  end

  @doc "Reads bytes `first..last` of an artifact, clamped to its size."
  def bytes(%{size: size, read: read, source_id: id}, first, last) do
    last = min(last, size - 1)
    started = System.monotonic_time(:millisecond)

    try do
      {:ok, if(first > last, do: "", else: read.(first, last))}
    rescue
      error ->
        log_failure(id, :artifact_bytes, started, :error, error, __STACKTRACE__)
        {:error, :storage_unavailable}
    catch
      kind, reason ->
        log_failure(id, :artifact_bytes, started, kind, reason, __STACKTRACE__)
        {:error, :storage_unavailable}
    end
  end

  def head(artifact, count), do: bytes(artifact, 0, count - 1)

  def field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  def text_name?(name),
    do: String.ends_with?(String.downcase(name), [".txt", ".log", ".json", ".csv"])

  @preview_chars 32_768
  # Enough bytes for the preview even if every character takes four.
  @preview_bytes @preview_chars * 4

  # Only the leading window is read, however large the attachment is.
  def preview(%{name: name, size: size} = artifact) do
    with true <- text_name?(name),
         {:ok, window} <- head(artifact, @preview_bytes),
         text when is_binary(text) <- valid_prefix(window, size > byte_size(window)) do
      %{
        text: String.slice(text, 0, @preview_chars),
        truncated: size > byte_size(window) or String.length(text) > @preview_chars
      }
    else
      _ -> %{text: nil, truncated: false}
    end
  end

  # A window cut out of a longer file may end inside a multibyte character.
  defp valid_prefix(window, cut?) do
    Enum.find_value(if(cut?, do: 0..3, else: [0]), fn drop ->
      keep = byte_size(window) - drop
      text = if keep >= 0, do: binary_part(window, 0, keep)
      if text && String.valid?(text), do: text
    end)
  end

  defp read(membership, id, operation, opts, fun) do
    started = System.monotonic_time(:millisecond)

    try do
      with {:ok, source} <- source(membership, id) do
        provider =
          Keyword.get(opts, :configuration, &Trifle.Traces.Source.Database.configuration/1)

        {:ok, fun.(provider.(source.record))}
      end
    rescue
      # A payload part over the configured size limits.
      error in Trifle.Traces.Error ->
        if error.reason == :too_large do
          {:error, :too_large}
        else
          log_failure(id, operation, started, :error, error, __STACKTRACE__)
          {:error, :storage_unavailable}
        end

      error ->
        log_failure(id, operation, started, :error, error, __STACKTRACE__)
        {:error, :storage_unavailable}
    catch
      :not_found ->
        {:error, :not_found}

      :too_large ->
        {:error, :too_large}

      kind, reason ->
        log_failure(id, operation, started, kind, reason, __STACKTRACE__)
        {:error, :storage_unavailable}
    end
  end

  defp log_failure(id, operation, started, kind, reason, stacktrace) do
    Logger.warning(fn ->
      "[Traces.Reader] operation=#{operation} source_id=#{id} " <>
        "elapsed_ms=#{System.monotonic_time(:millisecond) - started}\n" <>
        Exception.format(kind, reason, stacktrace)
    end)
  end

  @defaults [
    # A policy limit on what one download may pull through the app; attachments
    # are streamed, so this no longer bounds memory.
    max_artifact_bytes: 1024 * 1024 * 1024,
    artifact_chunk_bytes: 4 * 1024 * 1024,
    # Parts are decoded whole, so these do bound memory.
    max_part_bytes: 16 * 1024 * 1024,
    max_part_inflated_bytes: 64 * 1024 * 1024
  ]

  def setting(key) do
    Application.get_env(:trifle, __MODULE__, []) |> Keyword.get(key, @defaults[key])
  end

  defp find!(config, reference) do
    unless is_binary(reference) and byte_size(reference) <= 1024, do: throw(:not_found)
    Trifle.Traces.find(reference, config: config) || throw(:not_found)
  end

  defp read_part!(config, record, part) do
    # Reference, key and retention come from the tenant's index row and become
    # part of the storage path.
    unless is_integer(part) and part >= 1 and part <= record.parts and
             is_integer(record.retention) and record.retention > 0 and
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
