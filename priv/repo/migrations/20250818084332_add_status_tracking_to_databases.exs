defmodule Trifle.Repo.Migrations.AddStatusTrackingToDatabases do
  use Ecto.Migration

  def change do
    alter table(:databases) do
      add :last_check_at, :utc_datetime
      add :last_check_status, :string, default: "pending"
      add :last_error, :text
    end
  end
end