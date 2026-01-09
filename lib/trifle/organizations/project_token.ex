defmodule Trifle.Organizations.ProjectToken do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "project_tokens" do
    field :name, :string
    field :read, :boolean, default: false
    field :token, :string
    field :write, :boolean, default: false
    belongs_to :project, Trifle.Organizations.Project

    timestamps()
  end

  @doc false
  def changeset(project_token, attrs) do
    project = Map.get(attrs, "project") || Map.get(attrs, :project)

    attrs =
      attrs
      |> Map.delete("project")
      |> Map.delete(:project)

    project_token
    |> cast(attrs, [:name, :read, :write])
    |> maybe_put_project(project)
    |> put_change(
      :token,
      project_token.token ||
        if project do
          Phoenix.Token.sign(TrifleWeb.Endpoint, "project auth", project.id, max_age: 86400 * 365)
        end
    )
    |> validate_required([:project, :name, :token, :read, :write])
    |> unique_constraint(:token)
  end

  defp maybe_put_project(changeset, nil), do: changeset
  defp maybe_put_project(changeset, project), do: put_assoc(changeset, :project, project)
end
