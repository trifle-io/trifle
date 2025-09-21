defmodule Trifle.Repo.Migrations.CreateDashboards do
  use Ecto.Migration

  def change do
    create table(:dashboards, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :visibility, :boolean, default: false, null: false
      add :access_token, :string, null: false
      add :payload, :map, default: %{}, null: false
      add :key, :text, null: false

      add :database_id, references(:databases, on_delete: :delete_all, type: :binary_id),
        null: false

      timestamps()
    end

    create index(:dashboards, [:database_id])
    create unique_index(:dashboards, [:access_token])
  end
end
