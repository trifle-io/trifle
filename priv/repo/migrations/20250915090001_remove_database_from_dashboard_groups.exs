defmodule Trifle.Repo.Migrations.RemoveDatabaseFromDashboardGroups do
  use Ecto.Migration

  def up do
    # Drop indexes that reference database_id if they exist
    drop_if_exists index(:dashboard_groups, [:database_id])
    drop_if_exists index(:dashboard_groups, [:database_id, :parent_group_id, :position])

    # Remove the foreign key column
    alter table(:dashboard_groups) do
      remove :database_id
    end

    # Add a composite index to preserve predictable ordering within parent
    create index(:dashboard_groups, [:parent_group_id, :position])
  end

  def down do
    alter table(:dashboard_groups) do
      add :database_id, references(:databases, on_delete: :delete_all, type: :binary_id),
        null: false
    end

    create index(:dashboard_groups, [:database_id])
    create index(:dashboard_groups, [:parent_group_id])
    create index(:dashboard_groups, [:database_id, :parent_group_id, :position])

    drop_if_exists index(:dashboard_groups, [:parent_group_id, :position])
  end
end
