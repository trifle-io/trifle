defmodule TrifleApi.SourceController do
  use TrifleApi, :controller

  alias Trifle.Stats.Source

  plug(TrifleApi.Plugs.AuthenticateBySourceToken, %{mode: :any})

  def show(%{assigns: %{current_source: %Source{} = source}} = conn, _params) do
    render(conn, "show.json", source: source)
  end
end
