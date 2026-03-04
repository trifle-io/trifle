defmodule Trifle.Repo.Migrations.AddBeginningOfWeekToDatabases do
  use Ecto.Migration

  def change do
    alter table(:databases) do
      add :beginning_of_week, :integer, default: 1, null: false
    end
  end
end
