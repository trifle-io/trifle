defmodule TrifleApi.TranspondersJSON do
  alias Trifle.Organizations.Transponder

  def render("index.json", %{transponders: transponders}) do
    %{data: Enum.map(transponders, &format_transponder/1)}
  end

  def render("show.json", %{transponder: transponder}) do
    %{data: format_transponder(transponder)}
  end

  defp format_transponder(%Transponder{} = transponder) do
    %{
      id: transponder.id,
      name: transponder.name,
      key: transponder.key,
      type: transponder.type,
      config: transponder.config || %{},
      enabled: transponder.enabled,
      order: transponder.order,
      source_type: transponder.source_type,
      source_id: transponder.source_id
    }
  end
end
