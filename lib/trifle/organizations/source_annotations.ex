defmodule Trifle.Organizations.SourceAnnotations do
  @moduledoc """
  CRUD and dashboard grouping helpers for source-scoped annotations.
  """

  import Ecto.Query, warn: false

  alias Trifle.Organizations.OrganizationMembership
  alias Trifle.Organizations.SourceAnnotation
  alias Trifle.Repo
  alias Trifle.Stats.Nocturnal
  alias Trifle.Stats.Nocturnal.Parser
  alias Trifle.Stats.Source

  @max_grouped_lines 250
  @fallback_granularity "1h"

  @unit_seconds %{
    second: 1,
    minute: 60,
    hour: 3_600,
    day: 86_400,
    week: 604_800,
    month: 2_592_000,
    quarter: 7_776_000,
    year: 31_536_000
  }

  @spec list_for_source(
          OrganizationMembership.t(),
          Source.t(),
          DateTime.t(),
          DateTime.t(),
          String.t()
        ) ::
          [SourceAnnotation.t()]
  def list_for_source(
        %OrganizationMembership{} = membership,
        %Source{} = source,
        from,
        to,
        _granularity
      ) do
    with :ok <- authorize_source(membership, source),
         {:ok, from_utc} <- normalize_datetime(from),
         {:ok, to_utc} <- normalize_datetime(to) do
      source_type = source_type(source)
      source_id = Source.id(source)

      from(a in SourceAnnotation,
        where:
          a.organization_id == ^membership.organization_id and
            a.source_type == ^source_type and
            a.source_id == ^source_id and
            a.at >= ^from_utc and
            a.at <= ^to_utc,
        order_by: [asc: a.at, asc: a.inserted_at],
        preload: [:created_by_user, :updated_by_user]
      )
      |> Repo.all()
    else
      _ -> []
    end
  end

  @spec grouped_for_source(
          OrganizationMembership.t(),
          Source.t(),
          DateTime.t(),
          DateTime.t(),
          String.t()
        ) ::
          [map()]
  def grouped_for_source(
        %OrganizationMembership{} = membership,
        %Source{} = source,
        from,
        to,
        granularity
      ) do
    annotations = list_for_source(membership, source, from, to, granularity)

    build_groups(source, annotations, from, to, granularity)
  end

  def grouped_for_source(_membership, _source, _from, _to, _granularity), do: []

  @spec create_for_source(OrganizationMembership.t(), Source.t(), map()) ::
          {:ok, SourceAnnotation.t()} | {:error, term()}
  def create_for_source(%OrganizationMembership{} = membership, %Source{} = source, attrs)
      when is_map(attrs) do
    with :ok <- authorize_source(membership, source),
         {:ok, at, source_granularity} <-
           floor_source_timestamp(source, Map.get(attrs, "at") || Map.get(attrs, :at)) do
      attrs =
        attrs
        |> stringify_keys()
        |> Map.merge(%{
          "organization_id" => membership.organization_id,
          "source_type" => source_type(source),
          "source_id" => Source.id(source),
          "at" => at,
          "source_granularity" => source_granularity,
          "created_by_user_id" => membership.user_id,
          "updated_by_user_id" => membership.user_id
        })

      %SourceAnnotation{}
      |> SourceAnnotation.changeset(attrs)
      |> Repo.insert()
    end
  end

  @spec update_annotation(OrganizationMembership.t(), SourceAnnotation.t(), map()) ::
          {:ok, SourceAnnotation.t()} | {:error, term()}
  def update_annotation(
        %OrganizationMembership{} = membership,
        %SourceAnnotation{} = annotation,
        attrs
      )
      when is_map(attrs) do
    with :ok <- authorize_annotation(membership, annotation) do
      annotation
      |> SourceAnnotation.update_changeset(
        attrs
        |> stringify_keys()
        |> Map.put("updated_by_user_id", membership.user_id)
      )
      |> Repo.update()
    end
  end

  @spec delete_annotation(OrganizationMembership.t(), SourceAnnotation.t()) ::
          {:ok, SourceAnnotation.t()} | {:error, term()}
  def delete_annotation(%OrganizationMembership{} = membership, %SourceAnnotation{} = annotation) do
    with :ok <- authorize_annotation(membership, annotation) do
      Repo.delete(annotation)
    end
  end

  @spec get_annotation(OrganizationMembership.t(), binary()) :: SourceAnnotation.t() | nil
  def get_annotation(%OrganizationMembership{} = membership, id) when is_binary(id) do
    SourceAnnotation
    |> Repo.get_by(id: id, organization_id: membership.organization_id)
    |> Repo.preload([:created_by_user, :updated_by_user])
  end

  def get_annotation(_membership, _id), do: nil

  @spec floor_source_timestamp(Source.t(), DateTime.t() | String.t() | integer() | nil) ::
          {:ok, DateTime.t(), String.t()} | {:error, term()}
  def floor_source_timestamp(%Source{} = source, value) do
    with {:ok, datetime} <- normalize_datetime(value),
         granularity when is_binary(granularity) <- smallest_source_granularity(source),
         %Parser{} = parser <- Parser.new(granularity),
         true <- Parser.valid?(parser) do
      config = Source.stats_config(source)

      floored =
        datetime
        |> DateTime.shift_zone!(config.time_zone || "UTC")
        |> Nocturnal.new(config)
        |> Nocturnal.floor(parser.offset, parser.unit)
        |> DateTime.shift_zone!("Etc/UTC")

      {:ok, DateTime.truncate(floored, :microsecond), granularity}
    else
      false -> {:error, :invalid_granularity}
      nil -> {:error, :invalid_granularity}
      {:error, _} = error -> error
      _ -> {:error, :invalid_timestamp}
    end
  end

  def floor_source_timestamp(_source, _value), do: {:error, :invalid_source}

  def source_annotation_count(groups) when is_list(groups) do
    Enum.reduce(groups, 0, fn group, acc ->
      acc + (Map.get(group, :count) || Map.get(group, "count") || 0)
    end)
  end

  def source_annotation_count(_groups), do: 0

  defp build_groups(_source, [], _from, _to, _granularity), do: []

  defp build_groups(%Source{} = source, annotations, from, to, granularity) do
    source
    |> grouping_granularities(granularity)
    |> Enum.find_value(fn grouping_granularity ->
      groups = group_annotations(source, annotations, grouping_granularity)

      if length(groups) <= @max_grouped_lines do
        groups
      else
        nil
      end
    end)
    |> case do
      nil -> equal_bin_groups(annotations, from, to)
      groups -> groups
    end
  end

  defp group_annotations(%Source{} = source, annotations, granularity) do
    annotations
    |> Enum.group_by(fn annotation ->
      {:ok, grouped_at, _granularity} = floor_with_granularity(source, annotation.at, granularity)
      grouped_at
    end)
    |> Enum.map(fn {at, grouped_annotations} ->
      build_group(at, granularity, grouped_annotations)
    end)
    |> Enum.sort_by(& &1.at_ts)
  end

  defp floor_with_granularity(%Source{} = source, datetime, granularity) do
    with {:ok, datetime} <- normalize_datetime(datetime),
         %Parser{} = parser <- Parser.new(to_string(granularity)),
         true <- Parser.valid?(parser) do
      config = Source.stats_config(source)

      floored =
        datetime
        |> DateTime.shift_zone!(config.time_zone || "UTC")
        |> Nocturnal.new(config)
        |> Nocturnal.floor(parser.offset, parser.unit)
        |> DateTime.shift_zone!("Etc/UTC")

      {:ok, DateTime.truncate(floored, :microsecond), granularity}
    else
      _ -> floor_source_timestamp(source, datetime)
    end
  end

  defp equal_bin_groups(annotations, from, to) do
    with {:ok, from_dt} <- normalize_datetime(from),
         {:ok, to_dt} <- normalize_datetime(to) do
      from_us = DateTime.to_unix(from_dt, :microsecond)
      to_us = DateTime.to_unix(to_dt, :microsecond)
      span = max(to_us - from_us, 1)
      bin_size = max(div(span, @max_grouped_lines), 1)

      annotations
      |> Enum.group_by(fn annotation ->
        at_us = DateTime.to_unix(annotation.at, :microsecond)
        index = min(@max_grouped_lines - 1, max(0, div(at_us - from_us, bin_size)))
        from_us + index * bin_size
      end)
      |> Enum.map(fn {bucket_us, grouped_annotations} ->
        bucket_at = DateTime.from_unix!(bucket_us, :microsecond)
        build_group(bucket_at, "bin", grouped_annotations)
      end)
      |> Enum.sort_by(& &1.at_ts)
    else
      _ -> []
    end
  end

  defp build_group(at, granularity, annotations) do
    sorted = Enum.sort_by(annotations, &DateTime.to_unix(&1.at, :microsecond))
    at_iso = DateTime.to_iso8601(at)

    %{
      id: "annotation-group-#{DateTime.to_unix(at, :microsecond)}",
      at: at,
      at_iso: at_iso,
      at_ts: DateTime.to_unix(at, :millisecond),
      granularity: granularity,
      count: length(sorted),
      annotations: Enum.map(sorted, &serialize_annotation/1)
    }
  end

  defp serialize_annotation(%SourceAnnotation{} = annotation) do
    %{
      id: annotation.id,
      at_iso: DateTime.to_iso8601(annotation.at),
      at_ts: DateTime.to_unix(annotation.at, :millisecond),
      body: annotation.body,
      snippet: snippet(annotation.body),
      created_by_user_id: annotation.created_by_user_id,
      updated_by_user_id: annotation.updated_by_user_id,
      inserted_at: DateTime.to_iso8601(annotation.inserted_at),
      updated_at: DateTime.to_iso8601(annotation.updated_at)
    }
  end

  defp snippet(body) when is_binary(body) do
    body
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> then(fn text ->
      if String.length(text) > 160 do
        String.slice(text, 0, 157) <> "..."
      else
        text
      end
    end)
  end

  defp snippet(_body), do: ""

  defp grouping_granularities(%Source{} = source, granularity) do
    current =
      if valid_granularity?(granularity),
        do: to_string(granularity),
        else: smallest_source_granularity(source)

    current_seconds = granularity_seconds(current) || 0

    source
    |> Source.available_granularities()
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.filter(&valid_granularity?/1)
    |> Enum.sort_by(&granularity_seconds/1)
    |> Enum.filter(fn candidate -> (granularity_seconds(candidate) || 0) >= current_seconds end)
    |> then(fn candidates -> [current | candidates] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> [@fallback_granularity]
      list -> list
    end
  end

  defp smallest_source_granularity(%Source{} = source) do
    source
    |> Source.available_granularities()
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.filter(&valid_granularity?/1)
    |> Enum.sort_by(&granularity_seconds/1)
    |> List.first()
    |> Kernel.||(Source.default_granularity(source))
    |> Kernel.||(@fallback_granularity)
  end

  defp valid_granularity?(value) when is_binary(value) do
    value
    |> Parser.new()
    |> Parser.valid?()
  end

  defp valid_granularity?(_value), do: false

  defp granularity_seconds(value) when is_binary(value) do
    parser = Parser.new(value)

    if Parser.valid?(parser) do
      parser.offset * Map.fetch!(@unit_seconds, parser.unit)
    end
  end

  defp granularity_seconds(_value), do: nil

  defp authorize_source(%OrganizationMembership{} = membership, %Source{} = source) do
    if to_string(Source.organization_id(source)) == to_string(membership.organization_id) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp authorize_annotation(
         %OrganizationMembership{} = membership,
         %SourceAnnotation{} = annotation
       ) do
    if annotation.organization_id == membership.organization_id do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp source_type(%Source{} = source), do: source |> Source.type() |> Atom.to_string()

  defp normalize_datetime(%DateTime{} = datetime) do
    {:ok, datetime |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:microsecond)}
  end

  defp normalize_datetime(value) when is_integer(value) do
    DateTime.from_unix(value, :millisecond)
    |> case do
      {:ok, datetime} -> normalize_datetime(datetime)
      error -> error
    end
  end

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        normalize_datetime(datetime)

      {:error, _} = error ->
        error
    end
  end

  defp normalize_datetime(_value), do: {:error, :invalid_datetime}

  defp stringify_keys(map) do
    Enum.into(map, %{}, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end
end
