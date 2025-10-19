defmodule Trifle.Repo.Migrations.CreateSlackIntegrations do
  use Ecto.Migration

  def change do
    create table(:slack_installations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :team_id, :string, null: false
      add :team_name, :string, null: false
      add :team_domain, :string
      add :reference, :string, null: false
      add :bot_user_id, :string
      add :bot_access_token, :text, null: false
      add :scope, :string
      add :settings, :map, default: %{}
      add :installed_by_user_id,
          references(:users, type: :binary_id, on_delete: :nilify_all)

      add :last_channel_sync_at, :utc_datetime_usec

      timestamps()
    end

    create index(:slack_installations, [:organization_id])
    create unique_index(:slack_installations, [:organization_id, :team_id])
    create unique_index(:slack_installations, [:organization_id, :reference])

    create table(:slack_channels, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slack_installation_id,
          references(:slack_installations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :channel_id, :string, null: false
      add :name, :string, null: false
      add :channel_type, :string, null: false
      add :is_private, :boolean, default: false, null: false
      add :enabled, :boolean, default: false, null: false
      add :metadata, :map, default: %{}

      timestamps()
    end

    create unique_index(:slack_channels, [:slack_installation_id, :channel_id])
    create index(:slack_channels, [:slack_installation_id, :enabled])
  end
end
