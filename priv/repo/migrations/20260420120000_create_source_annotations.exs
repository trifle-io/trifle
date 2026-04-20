defmodule Trifle.Repo.Migrations.CreateSourceAnnotations do
  use Ecto.Migration

  def change do
    create table(:source_annotations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :source_type, :string, null: false
      add :source_id, :binary_id, null: false
      add :at, :utc_datetime_usec, null: false
      add :source_granularity, :string, null: false
      add :body, :text, null: false

      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :restrict),
        null: false

      add :updated_by_user_id, references(:users, type: :binary_id, on_delete: :restrict),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:source_annotations, [:organization_id, :source_type, :source_id, :at])
    create index(:source_annotations, [:created_by_user_id])
    create index(:source_annotations, [:updated_by_user_id])
  end
end
