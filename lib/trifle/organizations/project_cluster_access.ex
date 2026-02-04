defmodule Trifle.Organizations.ProjectClusterAccess do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "project_cluster_accesses" do
    belongs_to :project_cluster, Trifle.Organizations.ProjectCluster
    belongs_to :organization, Trifle.Organizations.Organization

    timestamps()
  end

  def changeset(access, attrs) do
    access
    |> cast(attrs, [:project_cluster_id, :organization_id])
    |> validate_required([:project_cluster_id, :organization_id])
    |> unique_constraint(:project_cluster_id,
      name: :project_cluster_accesses_cluster_org_index
    )
  end
end
