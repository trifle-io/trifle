defmodule Trifle.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :name, :string
      add :slug, :string
      add :time_zone, :string
      add :beginning_of_week, :integer
      add :user_id, references(:users, on_delete: :nothing)

      timestamps()
    end

    create index(:projects, [:user_id])
    create index(:projects, [:name])
    create unique_index(:projects, [:slug, :user_id])
  end
end
