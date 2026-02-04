defmodule Trifle.Repo.Migrations.AddProjectClusterConnectionStatus do
  use Ecto.Migration

  def change do
    alter table(:project_clusters) do
      add :last_check_at, :utc_datetime
      add :last_check_status, :string, null: false, default: "pending"
      add :last_error, :string
    end
  end
end
