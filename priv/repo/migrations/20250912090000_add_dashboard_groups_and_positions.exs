defmodule Trifle.Repo.Migrations.AddDashboardGroupsAndPositions do
  use Ecto.Migration

  def change do
    create table(:dashboard_groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :position, :integer, null: false, default: 0

      add :database_id, references(:databases, on_delete: :delete_all, type: :binary_id),
        null: false

      add :parent_group_id,
          references(:dashboard_groups, on_delete: :nilify_all, type: :binary_id)

      timestamps()
    end

    create index(:dashboard_groups, [:database_id])
    create index(:dashboard_groups, [:parent_group_id])
    create index(:dashboard_groups, [:database_id, :parent_group_id, :position])

    alter table(:dashboards) do
      add :group_id, references(:dashboard_groups, on_delete: :nilify_all, type: :binary_id)
      add :position, :integer, null: false, default: 0
    end

    create index(:dashboards, [:group_id])
    create index(:dashboards, [:database_id, :group_id, :position])
  end
end
