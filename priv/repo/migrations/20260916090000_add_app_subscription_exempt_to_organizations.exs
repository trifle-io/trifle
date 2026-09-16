defmodule Trifle.Repo.Migrations.AddAppSubscriptionExemptToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :app_subscription_exempt, :boolean, default: false, null: false
    end
  end
end
