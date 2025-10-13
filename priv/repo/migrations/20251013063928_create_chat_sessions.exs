defmodule Trifle.Repo.Migrations.CreateChatSessions do
  use Ecto.Migration

  def change do
    create table(:chat_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :source_type, :string, null: false
      add :source_id, :binary_id, null: false
      add :messages, {:array, :map}, default: [], null: false
      add :progress_events, {:array, :map}, default: [], null: false
      add :pending_started_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:chat_sessions, [:user_id, :organization_id, :source_type, :source_id],
             name: :chat_sessions_identity_index
           )
  end
end
