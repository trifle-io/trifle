defmodule TrifleApi.SourceJSON do
  alias Trifle.Billing
  alias Trifle.Stats.Source
  alias TrifleApi.Version

  def render("show.json", %{source: %Source{} = source}) do
    access = Billing.source_access_status(Source.type(source), Source.record(source))

    %{
      data: %{
        api_version: Version.api_version(),
        server_version: Version.server_version(),
        id: Source.id(source) |> to_string(),
        type: Source.type(source) |> Atom.to_string(),
        display_name: Source.display_name(source),
        default_timeframe: Source.default_timeframe(source),
        default_granularity: Source.default_granularity(source),
        available_granularities: Source.available_granularities(source) |> List.wrap(),
        time_zone: Source.time_zone(source),
        billing_state: access.billing_state,
        active: access.active?,
        inactive_reason: inactive_reason_payload(access.inactive_reason)
      }
    }
  end

  defp inactive_reason_payload(nil), do: nil

  defp inactive_reason_payload(reason),
    do: reason |> Billing.source_access_status_reason() |> Atom.to_string()
end
