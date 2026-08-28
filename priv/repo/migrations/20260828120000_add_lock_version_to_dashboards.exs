defmodule Trifle.Repo.Migrations.AddLockVersionToDashboards do
  use Ecto.Migration

  def change do
    alter table(:dashboards) do
      add :lock_version, :integer, null: false, default: 1
    end
  end
end
