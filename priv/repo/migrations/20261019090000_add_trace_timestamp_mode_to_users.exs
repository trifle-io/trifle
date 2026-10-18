defmodule Trifle.Repo.Migrations.AddTraceTimestampModeToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :trace_timestamp_mode, :string, default: "raw", null: false
    end
  end
end
