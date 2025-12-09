defmodule Trifle.Repo.Migrations.CreateDashboardVisits do
  use Ecto.Migration

  def change do
    create table(:dashboard_visits, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :dashboard_id,
          references(:dashboards, type: :binary_id, on_delete: :delete_all),
          null: false

      add :last_viewed_at, :utc_datetime_usec, null: false
      add :view_count, :integer, default: 0, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:dashboard_visits, [:organization_id])
    create index(:dashboard_visits, [:user_id])
    create index(:dashboard_visits, [:dashboard_id])

    create unique_index(:dashboard_visits, [:user_id, :dashboard_id],
             name: :dashboard_visits_user_dashboard_index
           )
  end
end
