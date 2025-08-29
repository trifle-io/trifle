defmodule Trifle.Repo.Migrations.AddNameToTransponders do
  use Ecto.Migration

  def change do
    alter table(:transponders) do
      add :name, :string
    end
  end
end
