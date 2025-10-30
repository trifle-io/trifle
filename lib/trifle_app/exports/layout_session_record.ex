defmodule TrifleApp.Exports.LayoutSessionRecord do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}

  schema "layout_sessions" do
    field :layout, :binary
    field :expires_at, :utc_datetime_usec

    timestamps(updated_at: false)
  end
end
