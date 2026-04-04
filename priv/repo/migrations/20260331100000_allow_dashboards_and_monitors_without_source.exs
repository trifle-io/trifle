defmodule Trifle.Repo.Migrations.AllowDashboardsAndMonitorsWithoutSource do
  use Ecto.Migration

  def change do
    alter table(:dashboards) do
      modify :source_type, :string, null: true
      modify :source_id, :binary_id, null: true
    end

    alter table(:monitors) do
      modify :source_type, :string, null: true
      modify :source_id, :binary_id, null: true
    end
  end
end
