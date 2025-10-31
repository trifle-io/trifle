defmodule Trifle.Repo.Migrations.AddSegmentValuesToMonitors do
  use Ecto.Migration

  def change do
    alter table(:monitors) do
      add :segment_values, :map, null: false, default: %{}
    end
  end
end

