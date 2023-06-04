defmodule Trifle.Organizations.ProjectToken do
  use Ecto.Schema
  import Ecto.Changeset

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
    project_token
    |> cast(attrs, [:name, :read, :write])
    |> put_assoc(:project,  attrs["project"])
    |> put_change(:token, (project_token.token || Phoenix.Token.sign(TrifleWeb.Endpoint, "project auth", attrs["project"].id)))
    |> validate_required([:project, :name, :token, :read, :write])
    |> unique_constraint(:token)
  end
end
