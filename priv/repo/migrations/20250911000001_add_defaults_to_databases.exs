defmodule Trifle.Repo.Migrations.AddDefaultsToDatabases do
  use Ecto.Migration

  def change do
    alter table(:databases) do
      add :default_timeframe, :string
      add :default_granularity, :string
    end
  end
end
