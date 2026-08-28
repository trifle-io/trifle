defmodule Trifle.Repo.Migrations.CreateDashboardTemplates do
  use Ecto.Migration

  def change do
    create table(:dashboard_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :lock_version, :integer, null: false, default: 1

      timestamps()
    end

    create index(:dashboard_templates, [:organization_id])
    create index(:dashboard_templates, [:created_by_id])
    create index(:dashboard_templates, [:organization_id, :name])

    alter table(:dashboards) do
      add :template_id, :text
    end

    create index(:dashboards, [:template_id])
  end
end
