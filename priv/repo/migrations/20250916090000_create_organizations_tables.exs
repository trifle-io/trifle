defmodule Trifle.Repo.Migrations.CreateOrganizationsTables do
  use Ecto.Migration

  def change do
    create table(:organizations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string
      add :address_line1, :string
      add :address_line2, :string
      add :city, :string
      add :state, :string
      add :postal_code, :string
      add :country, :string
      add :timezone, :string
      add :vat_number, :string
      add :registration_number, :string
      add :metadata, :map, default: %{}, null: false

      timestamps()
    end

    create unique_index(:organizations, [:slug])

    create table(:organization_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "member"
      add :invited_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :last_active_at, :utc_datetime

      timestamps()
    end

    create unique_index(:organization_memberships, [:organization_id, :user_id],
             name: :organization_memberships_org_user_index
           )

    create unique_index(:organization_memberships, [:user_id],
             name: :organization_memberships_user_unique
           )

    create table(:organization_invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :email, :string, null: false
      add :role, :string, null: false, default: "member"
      add :token, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :expires_at, :utc_datetime, null: false
      add :invited_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :accepted_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:organization_invitations, [:token])
    create index(:organization_invitations, [:email])
    create index(:organization_invitations, [:organization_id, :status])

    alter table(:databases) do
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :nothing)
    end

    alter table(:dashboards) do
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :nothing)
    end

    alter table(:dashboard_groups) do
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :nothing)
    end

    alter table(:transponders) do
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :nothing)
    end

    create index(:databases, [:organization_id])
    create index(:dashboards, [:organization_id])
    create index(:dashboard_groups, [:organization_id])
    create index(:transponders, [:organization_id])
  end
end
