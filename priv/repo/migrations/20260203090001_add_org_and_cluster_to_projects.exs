defmodule Trifle.Repo.Migrations.AddOrgAndClusterToProjects do
  use Ecto.Migration

  def up do
    alter table(:projects) do
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :nothing)

      add :project_cluster_id,
          references(:project_clusters, type: :binary_id, on_delete: :nothing)
    end

    create index(:projects, [:organization_id])
    create index(:projects, [:project_cluster_id])

    drop_if_exists index(:projects, [:slug, :user_id])

    execute("""
    UPDATE projects AS p
    SET organization_id = m.organization_id
    FROM organization_memberships AS m
    WHERE m.user_id = p.user_id
      AND p.organization_id IS NULL
    """)

    alter table(:projects) do
      modify :organization_id, :binary_id, null: false
    end

    # No slug column exists anymore; keep existing uniqueness behavior (none).
  end

  def down do
    drop index(:projects, [:project_cluster_id])
    drop index(:projects, [:organization_id])

    alter table(:projects) do
      remove :project_cluster_id
      remove :organization_id
    end
  end
end
