defmodule Trifle.Repo.Migrations.CreateOrganizationSsoProviders do
  use Ecto.Migration

  def change do
    create table(:organization_sso_providers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :provider, :string, null: false
      add :enabled, :boolean, null: false, default: true
      add :auto_provision_members, :boolean, null: false, default: true

      timestamps()
    end

    create unique_index(:organization_sso_providers, [:organization_id, :provider],
             name: :organization_sso_unique_provider_per_org
           )

    create table(:organization_sso_domains, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_sso_provider_id,
          references(:organization_sso_providers, type: :binary_id, on_delete: :delete_all),
          null: false

      add :domain, :string, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:organization_sso_domains, [:organization_sso_provider_id, :domain],
             name: :organization_sso_unique_domain_per_provider
           )

    execute(
      "CREATE UNIQUE INDEX organization_sso_unique_domain_global ON organization_sso_domains (lower(domain))",
      "DROP INDEX IF EXISTS organization_sso_unique_domain_global"
    )

    execute(
      "CREATE INDEX organization_sso_domains_lower_domain ON organization_sso_domains (lower(domain))",
      "DROP INDEX IF EXISTS organization_sso_domains_lower_domain"
    )
  end
end
