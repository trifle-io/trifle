defmodule Trifle.Repo.Migrations.CreateDiscordIntegrations do
  use Ecto.Migration

  def change do
    create table(:discord_installations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :guild_id, :string, null: false
      add :guild_name, :string, null: false
      add :guild_icon, :string
      add :reference, :string, null: false
      add :permissions, :string
      add :scope, :string
      add :settings, :map, default: %{}
      add :last_channel_sync_at, :utc_datetime_usec

      add :installed_by_user_id,
          references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create index(:discord_installations, [:organization_id])
    create unique_index(:discord_installations, [:organization_id, :guild_id])
    create unique_index(:discord_installations, [:organization_id, :reference])

    create table(:discord_channels, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :discord_installation_id,
          references(:discord_installations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :channel_id, :string, null: false
      add :name, :string, null: false
      add :channel_type, :string, null: false
      add :is_thread, :boolean, default: false, null: false
      add :enabled, :boolean, default: false, null: false
      add :metadata, :map, default: %{}

      timestamps()
    end

    create unique_index(:discord_channels, [:discord_installation_id, :channel_id])
    create index(:discord_channels, [:discord_installation_id, :enabled])
  end
end
