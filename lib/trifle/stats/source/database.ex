defmodule Trifle.Stats.Source.Database do
  @moduledoc """
  Source implementation backed by a Trifle organizations database.
  """

  @behaviour Trifle.Stats.Source.Behaviour

  alias Trifle.Organizations
  alias Trifle.Organizations.Database

  @impl true
  def type(_database), do: :database

  @impl true
  def id(%Database{id: id}), do: id

  @impl true
  def organization_id(%Database{organization_id: organization_id}), do: organization_id

  @impl true
  def display_name(%Database{display_name: name}), do: name

  @impl true
  def stats_config(%Database{} = database), do: Database.stats_config(database)

  @impl true
  def default_timeframe(%Database{default_timeframe: timeframe}), do: timeframe

  @impl true
  def default_granularity(%Database{default_granularity: granularity}), do: granularity

  @impl true
  def available_granularities(%Database{} = database) do
    config = Database.stats_config(database)
    config.track_granularities
  end

  @impl true
  def time_zone(%Database{time_zone: time_zone}), do: time_zone || "UTC"

  @impl true
  def transponders(%Database{} = database) do
    Organizations.list_transponders_for_database(database)
  end
end
