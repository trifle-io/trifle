defmodule TrifleApp.Layouts do
  use TrifleApp, :html

  embed_templates "layouts/*"

  def gravatar(email) do
    hash = email
      |> String.trim()
      |> String.downcase()
      |> :erlang.md5()
      |> Base.encode16(case: :lower)

    img = "https://www.gravatar.com/avatar/#{hash}?s=150&d=identicon"
    # img_tag(img, class: "h-8 w-8 rounded-full")
    Phoenix.HTML.raw("<img src=#{img} class='h-8 w-8 rounded-full'></img>")
  end
end
