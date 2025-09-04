defmodule Trifle.Repo.Migrations.AddUserToDashboards do
  use Ecto.Migration

  def change do
    alter table(:dashboards) do
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id)
      modify :access_token, :string, null: true  # Make access_token nullable for public links
    end

    create index(:dashboards, [:user_id])
  end
end