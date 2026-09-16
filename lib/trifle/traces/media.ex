defmodule Trifle.Traces.Media do
  @moduledoc "A restricted set of trace attachments that can be rendered inline."

  @types %{
    ".png" => {:image, "image/png"},
    ".jpg" => {:image, "image/jpeg"},
    ".jpeg" => {:image, "image/jpeg"},
    ".gif" => {:image, "image/gif"},
    ".webp" => {:image, "image/webp"},
    ".mp4" => {:video, "video/mp4"},
    ".webm" => {:video, "video/webm"}
  }

  def type(name) when is_binary(name),
    do: Map.get(@types, name |> Path.extname() |> String.downcase())

  def type(_), do: nil

  # Never serve arbitrary HTML/SVG or a caller-supplied MIME type on the app origin.
  # The header check catches mislabeled files; decoding remains the browser's job.
  def content_type(%{name: name, body: body}) do
    with {_, mime} <- type(name), true <- matches?(mime, body), do: mime, else: (_ -> nil)
  end

  defp matches?("image/png", <<137, "PNG\r\n", 26, "\n", _::binary>>), do: true
  defp matches?("image/jpeg", <<255, 216, 255, _::binary>>), do: true

  defp matches?("image/gif", <<header::binary-size(6), _::binary>>)
       when header in ["GIF87a", "GIF89a"],
       do: true

  defp matches?("image/webp", <<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: true
  defp matches?("video/webm", <<26, 69, 223, 163, _::binary>>), do: true
  defp matches?("video/mp4", <<_::binary-size(4), "ftyp", _::binary>>), do: true
  defp matches?(_, _), do: false
end
