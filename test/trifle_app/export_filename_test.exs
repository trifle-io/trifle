defmodule TrifleApp.ExportFilenameTest do
  use ExUnit.Case, async: true

  alias TrifleApp.ExportFilename

  test "joins prefix and parts with sanitized components" do
    filename = ExportFilename.build("dashboard", ["My Dashboard!"], ".csv")

    assert filename =~ ~r/^dashboard-My-Dashboard--\d{8}T\d{6}Z\.csv$/
  end

  test "drops nil parts" do
    filename = ExportFilename.build("explore", [nil, "page_views"], ".json")

    assert filename =~ ~r/^explore-page_views-\d{8}T\d{6}Z\.json$/
  end

  test "works with no parts" do
    filename = ExportFilename.build("monitor", [], ".csv")

    assert filename =~ ~r/^monitor-\d{8}T\d{6}Z\.csv$/
  end

  test "sanitizes special characters in parts" do
    filename = ExportFilename.build("export", ["a/b c@d"], ".png")

    assert filename =~ ~r/^export-a-b-c-d-\d{8}T\d{6}Z\.png$/
  end
end
