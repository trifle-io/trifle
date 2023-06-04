defmodule Trifle.Organizations.Project do
  use Ecto.Schema
  import Ecto.Changeset
  import Slugy

  schema "projects" do
    field :beginning_of_week, :integer
    field :name, :string
    field :slug, :string
    field :time_zone, :string
    field :user_id, :id
    has_many :project_tokens, Trifle.Organizations.ProjectToken

    timestamps()
  end

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :slug, :time_zone, :beginning_of_week])
    |> slugify(:name)
    |> validate_required([:name, :slug, :time_zone, :beginning_of_week])
  end
end
