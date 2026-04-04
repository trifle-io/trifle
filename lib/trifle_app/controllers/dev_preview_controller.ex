defmodule TrifleApp.DevPreviewController do
  use TrifleApp, :controller

  def error_404(conn, _params) do
    render_error(conn, :not_found, "404.html")
  end

  def error_500(conn, _params) do
    render_error(conn, :internal_server_error, "500.html")
  end

  defp render_error(conn, status, template) do
    conn
    |> put_status(status)
    |> put_view(html: TrifleApp.ErrorHTML)
    |> put_layout(false)
    |> render(template)
  end
end
