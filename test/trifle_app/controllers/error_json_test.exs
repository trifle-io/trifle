defmodule TrifleApp.ErrorJSONTest do
  use TrifleApp.ConnCase, async: true

  test "renders 404" do
    assert TrifleApp.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert TrifleApp.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
