defmodule TrifleApi.DashboardsJSON do
  alias Trifle.Organizations.Dashboard

  def render("index.json", %{dashboards: dashboards}) do
    %{data: Enum.map(dashboards, &format_dashboard/1)}
  end

  def render("show.json", %{dashboard: dashboard}) do
    %{data: format_dashboard(dashboard)}
  end

  defp format_dashboard(%Dashboard{} = dashboard) do
    %{
      id: dashboard.id,
      name: dashboard.name,
      key: dashboard.key,
      visibility: dashboard.visibility,
      locked: dashboard.locked,
      source_type: dashboard.source_type,
      source_id: dashboard.source_id,
      organization_id: dashboard.organization_id,
      user_id: dashboard.user_id,
      database_id: dashboard.database_id,
      group_id: dashboard.group_id,
      position: dashboard.position,
      default_timeframe: dashboard.default_timeframe,
      default_granularity: dashboard.default_granularity,
      payload: dashboard.payload || %{},
      segments: dashboard.segments || [],
      inserted_at: format_datetime(dashboard.inserted_at),
      updated_at: format_datetime(dashboard.updated_at)
    }
  end

  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_datetime(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  defp format_datetime(_), do: nil
end
