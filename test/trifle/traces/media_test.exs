defmodule Trifle.Traces.MediaTest do
  use ExUnit.Case, async: true
  alias Trifle.Traces.Media

  test "only known raster images and browser video containers are inline candidates" do
    for {name, kind, mime, body} <- [
          {"IMAGE.PNG", :image, "image/png", <<137, "PNG\r\n", 26, "\n", 0>>},
          {"image.jpg", :image, "image/jpeg", <<255, 216, 255, 0>>},
          {"image.jpeg", :image, "image/jpeg", <<255, 216, 255, 0>>},
          {"image.gif", :image, "image/gif", "GIF89a"},
          {"image.webp", :image, "image/webp", "RIFF0000WEBP"},
          {"clip.webm", :video, "video/webm", <<26, 69, 223, 163, 0>>},
          {"clip.mp4", :video, "video/mp4", <<0, 0, 0, 20, "ftypisom">>}
        ] do
      assert Media.type(name) == {kind, mime}
      assert Media.content_type(%{name: name, body: body}) == mime
      assert Media.content_type(%{name: name, body: "<html>not media</html>"}) == nil
    end

    for name <- [nil, "image.svg", "page.html", "report.txt", "unknown", "image.png.html"] do
      assert Media.type(name) == nil
      assert Media.content_type(%{name: name, body: "body"}) == nil
    end
  end
end
