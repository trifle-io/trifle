defmodule Trifle.Stats.Source.Project do
  @moduledoc """
  Source implementation backed by a Trifle project.
  """

  @behaviour Trifle.Stats.Source.Behaviour

  alias Trifle.Organizations.Project

  @impl true
  def type(_project), do: :project

  @impl true
  def id(%Project{id: id}), do: id

  @impl true
  def organization_id(%Project{}), do: nil

  @impl true
  def display_name(%Project{name: name}), do: name || "Project"

  @impl true
  def stats_config(%Project{} = project), do: Project.stats_config(project)

  @impl true
  def default_timeframe(%Project{default_timeframe: timeframe}), do: timeframe

  @impl true
  def default_granularity(%Project{default_granularity: granularity}), do: granularity

  @impl true
  def available_granularities(%Project{} = project) do
    case project.granularities do
      list when is_list(list) and list != [] -> list
      _ -> Project.default_granularities()
    end
  end

  @impl true
  def time_zone(%Project{time_zone: time_zone}), do: time_zone || "UTC"

  @impl true
  def transponders(_project), do: []
end
