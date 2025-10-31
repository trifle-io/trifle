defmodule Trifle.Repo.Migrations.AddDeliveryMediaToMonitors do
  use Ecto.Migration

  def change do
    alter table(:monitors) do
      add :delivery_media, {:array, :map}, null: false, default: []
    end
  end
end
