defmodule Trifle.Repo.Migrations.AddSetupStatusToDatabases do
  use Ecto.Migration

  def change do
    alter table(:databases) do
      add :setup_status, :string, default: "pending"
    end
  end
end