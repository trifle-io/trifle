defmodule Trifle.Stats.Source do
  @moduledoc """
  Wrapper for analytics sources (e.g., databases) that can provide stats
  configuration, defaults, and metadata to LiveViews and fetchers.
  """

  @enforce_keys [:module, :record]
  defstruct [:module, :record]

  alias __MODULE__.Behaviour
  alias Trifle.Organizations
  alias Trifle.Organizations.Project, as: OrgProject
  alias Trifle.Organizations.OrganizationMembership
  alias Trifle.Stats.SeriesFetcher
  alias Trifle.Stats.Source.Database
  alias Trifle.Stats.Source.Project, as: SourceProject

  defmodule Behaviour do
    @callback type(struct()) :: atom()
    @callback id(struct()) :: term()
    @callback organization_id(struct()) :: term()
    @callback display_name(struct()) :: String.t()
    @callback stats_config(struct()) :: struct()
    @callback default_timeframe(struct()) :: String.t() | nil
    @callback default_granularity(struct()) :: String.t() | nil
    @callback available_granularities(struct()) :: [String.t()]
    @callback time_zone(struct()) :: String.t()
    @callback transponders(struct()) :: list()
  end

  @type t :: %__MODULE__{module: module(), record: struct()}

  @spec new(module(), struct()) :: t()
  def new(module, record) when is_atom(module) and is_struct(record) do
    %__MODULE__{module: module, record: record}
  end

  @spec from_database(Trifle.Organizations.Database.t()) :: t()
  def from_database(%Trifle.Organizations.Database{} = database) do
    new(Database, database)
  end

  @spec from_project(OrgProject.t()) :: t()
  def from_project(%OrgProject{} = project) do
    new(SourceProject, project)
  end

  @spec record(t()) :: struct()
  def record(%__MODULE__{record: record}), do: record

  @spec with_record(t(), struct()) :: t()
  def with_record(%__MODULE__{} = source, record) when is_struct(record) do
    %__MODULE__{source | record: record}
  end

  @spec type(t()) :: atom()
  def type(source), do: delegate(source, :type)

  @spec id(t()) :: term()
  def id(source), do: delegate(source, :id)

  @spec organization_id(t()) :: term()
  def organization_id(source), do: delegate(source, :organization_id)

  @spec display_name(t()) :: String.t()
  def display_name(source), do: delegate(source, :display_name)

  @spec stats_config(t()) :: struct()
  def stats_config(source), do: delegate(source, :stats_config)

  @spec default_timeframe(t()) :: String.t() | nil
  def default_timeframe(source), do: delegate(source, :default_timeframe)

  @spec default_granularity(t()) :: String.t() | nil
  def default_granularity(source), do: delegate(source, :default_granularity)

  @spec available_granularities(t()) :: [String.t()]
  def available_granularities(source), do: delegate(source, :available_granularities)

  @spec time_zone(t()) :: String.t()
  def time_zone(source), do: delegate(source, :time_zone)

  @spec transponders(t()) :: list()
  def transponders(source), do: delegate(source, :transponders)

  @spec reference(t()) :: %{type: atom(), id: term()}
  def reference(source) do
    %{type: type(source), id: id(source)}
  end

  @spec type_string(t()) :: String.t()
  def type_string(source), do: source |> type() |> Atom.to_string()

  @spec list_for_membership(OrganizationMembership.t() | nil) :: [t()]
  def list_for_membership(nil), do: []

  def list_for_membership(%OrganizationMembership{organization_id: org_id, user_id: user_id}) do
    databases = list_for_organization(org_id)

    projects =
      Organizations.list_projects()
      |> Enum.filter(&(&1.user_id == user_id))
      |> Enum.map(&from_project/1)

    (databases ++ projects)
    |> sort_sources()
  end

  @spec list_for_organization(term()) :: [t()]
  def list_for_organization(nil), do: []

  def list_for_organization(org_id) do
    Organizations.list_databases_for_org(org_id)
    |> Enum.map(&from_database/1)
    |> sort_sources()
  end

  @spec find_in_list([t()], atom(), term()) :: t() | nil
  def find_in_list(sources, type, id) do
    type_atom = normalize_type(type)
    id_str = id |> to_string()

    Enum.find(sources, fn source ->
      type(source) == type_atom && to_string(id(source)) == id_str
    end)
  end

  @spec type_label(atom()) :: String.t()
  def type_label(:database), do: "Databases"
  def type_label(:project), do: "Projects"
  def type_label(other), do: other |> Atom.to_string() |> String.capitalize()

  @spec fetch_series(
          t(),
          String.t() | nil,
          DateTime.t(),
          DateTime.t(),
          String.t(),
          Keyword.t()
        ) ::
          {:ok, map()} | {:error, term()}
  def fetch_series(%__MODULE__{} = source, key, from, to, granularity, opts \\ []) do
    {transponders, opts} = resolve_transponders(source, key, opts)

    SeriesFetcher.fetch_series(
      source,
      key || "",
      from,
      to,
      granularity,
      transponders,
      opts
    )
  end

  @spec matching_transponders(t(), String.t() | nil) :: list()
  def matching_transponders(%__MODULE__{} = source, key) do
    source
    |> transponders()
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&Map.get(&1, :enabled, false))
    |> Enum.filter(fn transponder -> key_matches_pattern?(key, Map.get(transponder, :key)) end)
    |> Enum.sort_by(&Map.get(&1, :order, 0))
  end

  defp resolve_transponders(source, key, opts) do
    case Keyword.get(opts, :transponders, :auto) do
      :auto ->
        {matching_transponders(source, key), Keyword.delete(opts, :transponders)}

      :none ->
        {[], Keyword.delete(opts, :transponders)}

      transponders when is_list(transponders) ->
        {transponders, Keyword.delete(opts, :transponders)}
    end
  end

  defp key_matches_pattern?(key, pattern) do
    key = key || ""
    pattern = pattern || ""

    cond do
      pattern == "" ->
        key == ""

      String.contains?(pattern, "^") or String.contains?(pattern, "$") ->
        case Regex.compile(pattern) do
          {:ok, regex} -> Regex.match?(regex, key)
          {:error, _} -> false
        end

      true ->
        key == pattern
    end
  end

  defp sort_sources(sources) do
    sources
    |> Enum.sort_by(fn source ->
      {
        type_sort_key(type(source)),
        display_name(source) |> String.downcase()
      }
    end)
  end

  defp type_sort_key(:database), do: 0
  defp type_sort_key(:project), do: 1
  defp type_sort_key(_other), do: 2

  defp normalize_type(type) when is_atom(type), do: type

  defp normalize_type(type) when is_binary(type) do
    case String.trim(type) do
      "" -> nil
      "database" -> :database
      "project" -> :project
      other -> String.to_atom(other)
    end
  rescue
    ArgumentError -> nil
  end

  defp normalize_type(_), do: nil

  defp delegate(%__MODULE__{module: module, record: record}, function) do
    apply(module, function, [record])
  end
end
