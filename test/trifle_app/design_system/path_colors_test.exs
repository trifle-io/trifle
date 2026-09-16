defmodule TrifleApp.DesignSystem.PathColorsTest do
  use ExUnit.Case, async: true

  alias TrifleApp.DesignSystem.{ChartColors, PathColors}
  alias TrifleApp.ExploreCore

  test "each parent assigns its own alphabetically ordered sibling colors" do
    paths = ["jobs/last", "jobs/first", "jobs", "requests/last", "jobs/first/deep"]
    colors = PathColors.build(paths, "/")

    assert colors[["jobs"]] == ChartColors.color_for(0)
    assert colors[["jobs", "first"]] == ChartColors.color_for(0)
    assert colors[["jobs", "last"]] == ChartColors.color_for(1)
    assert colors[["requests"]] == ChartColors.color_for(1)
    assert colors[["requests", "last"]] == ChartColors.color_for(0)
    assert colors[["jobs", "first", "deep"]] == ChartColors.color_for(0)
    assert colors == PathColors.build(Enum.reverse(paths) ++ paths, "/")
  end

  test "trace labels split only on slash, preserving literal dots and other characters" do
    worker = ~S(Trifle.Monitors.Jobs.Test*%2E\Worker)
    path = "jobs/" <> worker

    html =
      path |> PathColors.html(PathColors.build([path], "/"), "/") |> Phoenix.HTML.safe_to_string()

    {:ok, doc} = Floki.parse_fragment(html)

    assert Enum.map(Floki.find(doc, "span"), &Floki.text/1) == ["jobs/", worker]
    assert Floki.text(doc) == path
    assert Enum.count(Floki.find(doc, "span")) == 2
  end

  test "shared Stats rendering keeps dotted hierarchy and explicit escaping" do
    colors = PathColors.build(["jobs.first", "jobs.last", ~S(jobs.test\.rb), ~S(jobs.\*)])
    assert colors[["jobs", "test.rb"]] == ChartColors.color_for(3)
    assert colors[["jobs", "*"]] == ChartColors.color_for(0)

    html = ExploreCore.format_nested_path("jobs.last", ["jobs.first", "jobs.last"])

    assert Phoenix.HTML.safe_to_string(html) ==
             ~s(<span style="color: #{ChartColors.color_for(0)} !important">jobs</span>.<span style="color: #{ChartColors.color_for(1)} !important">last</span>)
  end

  test "trace labels escape HTML and include each slash in the preceding colored segment" do
    path = "jobs/<img src=x onerror=alert(1)>"

    html =
      path |> PathColors.html(PathColors.build([path], "/"), "/") |> Phoenix.HTML.safe_to_string()

    assert html =~ "jobs/</span><span"
    assert html =~ "&lt;img src=x onerror=alert(1)&gt;"
    refute html =~ "<img"
  end

  test "trace slash coloring preserves full paths, including empty segments" do
    for path <- ["jobs", "jobs/first/deep", "/jobs//first/"] do
      colors = PathColors.build([path, "jobs/another"], "/")

      doc =
        path
        |> PathColors.html(colors, "/")
        |> Phoenix.HTML.safe_to_string()
        |> Floki.parse_fragment!()

      segments = Floki.find(doc, "span")
      assert Floki.text(doc) == path
      assert Enum.all?(Enum.drop(segments, -1), &String.ends_with?(Floki.text(&1), "/"))

      prefixes =
        path |> String.split("/") |> Enum.scan([], fn part, prefix -> prefix ++ [part] end)

      assert Floki.attribute(segments, "style") ==
               Enum.map(prefixes, &"color: #{colors[&1]} !important")
    end
  end

  test "colors cycle through the existing palette for large sibling sets" do
    paths = for n <- 0..13, do: "jobs/" <> String.pad_leading(to_string(n), 2, "0")
    assert PathColors.build(paths, "/")[["jobs", "13"]] == ChartColors.color_for(13)
  end
end
