defmodule Trifle.Repo.Migrations.AddTimeZoneToDatabases do
  use Ecto.Migration

  def change do
    alter table(:databases) do
      add :time_zone, :string, default: "UTC"
    end
  end
end