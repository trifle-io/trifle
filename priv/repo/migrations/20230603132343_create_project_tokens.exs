defmodule Trifle.Repo.Migrations.CreateProjectTokens do
  use Ecto.Migration

  def change do
    create table(:project_tokens) do
      add :name, :string
      add :token, :string
      add :read, :boolean, default: false, null: false
      add :write, :boolean, default: false, null: false
      add :project_id, references(:projects, on_delete: :nothing)

      timestamps()
    end

    create index(:project_tokens, [:project_id])
  end
end
