defmodule Trifle.Organizations.DashboardGroup do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dashboard_groups" do
    field :name, :string
    field :position, :integer, default: 0

    belongs_to :parent_group, __MODULE__, foreign_key: :parent_group_id

    has_many :children, __MODULE__, foreign_key: :parent_group_id
    has_many :dashboards, Trifle.Organizations.Dashboard, foreign_key: :group_id

    timestamps()
  end

  def changeset(group, attrs) do
    group
    |> cast(attrs, [:name, :position, :parent_group_id])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end
end
