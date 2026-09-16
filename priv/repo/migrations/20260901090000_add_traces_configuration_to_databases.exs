defmodule Trifle.Repo.Migrations.AddTracesConfigurationToDatabases do
  use Ecto.Migration

  def change do
    alter table(:databases) do
      add :trace_config, :map, null: false, default: fragment("'{}'::jsonb")
      add :trace_access_key_id, :binary
      add :trace_secret_access_key, :binary
      add :managed_key, :string
    end

    create unique_index(:databases, [:managed_key],
             where: "managed_key IS NOT NULL",
             name: :databases_managed_key_unique
           )
  end
end
