defmodule Trifle.Repo.Migrations.AddLockToDashboards do
  use Ecto.Migration

  def change do
    alter table(:dashboards) do
      add :locked, :boolean, default: false, null: false
    end
  end
end
