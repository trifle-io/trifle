defmodule Trifle.Repo do
  use Ecto.Repo,
    otp_app: :trifle,
    adapter: Ecto.Adapters.Postgres
end
