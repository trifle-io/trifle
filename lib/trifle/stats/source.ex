defmodule Trifle.Stats.Source do
  @moduledoc """
  Wrapper for analytics sources (e.g., databases) that can provide stats
  configuration, defaults, and metadata to LiveViews and fetchers.
  """

  @enforce_keys [:module, :record]
  defstruct [:module, :record]

  alias __MODULE__.Behaviour

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
    new(Trifle.Stats.Source.Database, database)
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

  defp delegate(%__MODULE__{module: module, record: record}, function) do
    apply(module, function, [record])
  end
end
