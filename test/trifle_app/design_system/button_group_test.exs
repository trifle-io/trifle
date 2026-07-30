defmodule TrifleApp.DesignSystem.ButtonGroupTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  defmodule Harness do
    use Phoenix.Component

    import TrifleApp.DesignSystem.ButtonGroup

    def examples(assigns) do
      ~H"""
      <div>
        <.button_group label="Icon controls" labels="hidden" class="icon-controls">
          <:button label="Line" selected={true}>
            <span data-test-icon="line">icon</span>
          </:button>
        </.button_group>

        <.button_group label="Text controls" class="text-controls">
          <:button label="List" selected={false} />
        </.button_group>

        <.button_group label="Responsive controls" labels="responsive">
          <:button label="Area">
            <span data-test-icon="area">icon</span>
          </:button>
          <:button label="Bar" tooltip="Compare grouped values">
            <span data-test-icon="bar">icon</span>
          </:button>
        </.button_group>

        <.button_group labels="visible">
          <:button label="Legacy" title="Legacy tooltip" />
        </.button_group>
      </div>
      """
    end
  end

  test "renders icon-only buttons with automatic tooltips and accessible state" do
    document = render_document()

    [button] = Floki.find(document, ".icon-controls button")

    assert Floki.attribute(button, "aria-label") == ["Line"]
    assert Floki.attribute(button, "aria-pressed") == ["true"]
    assert Floki.attribute(button, "data-tooltip") == ["Line"]
    assert Floki.attribute(button, "data-tooltip-media") == []
    assert button |> Floki.text() |> String.trim() == "icon"
  end

  test "renders text-only buttons without redundant automatic tooltips" do
    document = render_document()

    [button] = Floki.find(document, ".text-controls button")

    assert Floki.attribute(button, "aria-label") == ["List"]
    assert Floki.attribute(button, "aria-pressed") == ["false"]
    assert Floki.attribute(button, "data-tooltip") == []
    assert button |> Floki.text() |> String.trim() == "List"
  end

  test "limits automatic responsive tooltips to the label-hidden breakpoint" do
    document = render_document()
    [automatic, explicit] = Floki.find(document, ~s([aria-label="Responsive controls"] button))

    assert Floki.attribute(automatic, "data-tooltip") == ["Area"]
    assert Floki.attribute(automatic, "data-tooltip-media") == ["(max-width: 767px)"]
    assert Floki.find(automatic, "span.hidden.md\\:inline") != []

    assert Floki.attribute(explicit, "data-tooltip") == ["Compare grouped values"]
    assert Floki.attribute(explicit, "data-tooltip-media") == []
  end

  test "normalizes legacy title attributes to the shared JS tooltip" do
    document = render_document()
    [button] = Floki.find(document, ~s(button[aria-label="Legacy"]))

    assert Floki.attribute(button, "data-tooltip") == ["Legacy tooltip"]
    assert Floki.attribute(button, "title") == []
  end

  defp render_document do
    render_component(&Harness.examples/1, %{})
    |> Floki.parse_fragment!()
  end
end
