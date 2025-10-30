defmodule Trifle.Repo.Migrations.CreateLayoutSessions do
  use Ecto.Migration

  def change do
    create table(:layout_sessions, primary_key: false) do
      add :id, :string, primary_key: true
      add :layout, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(updated_at: false)
    end

    create index(:layout_sessions, [:expires_at])
  end
end
