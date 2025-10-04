defmodule Trifle.Repo.Migrations.AddSegmentsToDashboards do
  use Ecto.Migration

  def change do
    alter table(:dashboards) do
      add(:segments, {:array, :map}, default: [], null: false)
    end
  end
end
