defmodule Trifle.Repo.Migrations.CreateProjectClusters do
  use Ecto.Migration

  def change do
    create table(:project_clusters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :code, :string, null: false
      add :driver, :string, null: false
      add :status, :string, null: false, default: "active"
      add :visibility, :string, null: false, default: "public"
      add :is_default, :boolean, null: false, default: false
      add :region, :string
      add :country, :string
      add :city, :string
      add :host, :string
      add :port, :integer
      add :database_name, :binary
      add :username, :binary
      add :password, :binary
      add :auth_database, :binary
      add :config, :map, default: %{}

      timestamps()
    end

    create unique_index(:project_clusters, [:code])
    create unique_index(:project_clusters, [:is_default], where: "is_default")
    create index(:project_clusters, [:driver])
    create index(:project_clusters, [:status])
    create index(:project_clusters, [:visibility])

    create table(:project_cluster_accesses, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_cluster_id,
          references(:project_clusters, type: :binary_id, on_delete: :delete_all),
          null: false

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps()
    end

    create unique_index(:project_cluster_accesses, [:project_cluster_id, :organization_id],
             name: :project_cluster_accesses_cluster_org_index
           )

    create index(:project_cluster_accesses, [:organization_id])
  end
end
