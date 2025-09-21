defmodule Trifle.Repo.Migrations.AddOrderToTransponders do
  use Ecto.Migration

  def change do
    alter table(:transponders) do
      add :order, :integer, default: 0
    end

    create index(:transponders, [:database_id, :order])
  end
end
