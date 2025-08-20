defmodule Trifle.Repo.Migrations.RemoveSetupStatusFromDatabases do
  use Ecto.Migration

  def change do
    alter table(:databases) do
      remove :setup_status
    end
  end
end