defmodule TrifleWeb.PageController do
  use TrifleWeb, :controller

  plug :put_layout, html: {TrifleWeb.Layouts, :page}

  def home(conn, _params) do
    redirect(conn, to: ~p"/dashboards")
  end

  def home_page(conn, _params) do
    render(conn, :home, layout: false)
  end

  def toc(conn, _params) do
    render(conn, :toc)
  end

  def privacy(conn, _params) do
    render(conn, :privacy)
  end
end
