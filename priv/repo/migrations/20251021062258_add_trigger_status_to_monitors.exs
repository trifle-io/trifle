defmodule Trifle.Repo.Migrations.AddTriggerStatusToMonitors do
  use Ecto.Migration

  def change do
    alter table(:monitors) do
      add :trigger_status, :string, null: false, default: "idle"
    end
  end
end
