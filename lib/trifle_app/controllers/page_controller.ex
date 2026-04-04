defmodule TrifleApp.PageController do
  use TrifleApp, :controller

  plug :put_layout, html: {TrifleApp.Layouts, :page}

  def toc(conn, _params) do
    render(conn, :toc)
  end

  def privacy(conn, _params) do
    render(conn, :privacy)
  end
end
