defmodule Trifle.Repo.Migrations.AddDefaultsToDashboards do
  use Ecto.Migration

  def change do
    alter table(:dashboards) do
      add :default_timeframe, :string
      add :default_granularity, :string
    end
  end
end

