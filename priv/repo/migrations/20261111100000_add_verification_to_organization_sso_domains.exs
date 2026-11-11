defmodule Trifle.Repo.Migrations.AddVerificationToOrganizationSsoDomains do
  use Ecto.Migration

  # SSO domains now need proof of ownership (a DNS TXT record) before they route
  # sign-ins to an organization.
  #
  # Domains that already exist are marked verified so working sign-in is not
  # interrupted; review them once after deploying (see docs/backlog/security.md).
  #
  # The "one organization per domain" rule moves from all claims to verified
  # claims only, so an unverified claim can no longer block the real owner.
  def up do
    alter table(:organization_sso_domains) do
      add :verification_token, :string
      add :verified_at, :utc_datetime
    end

    execute("UPDATE organization_sso_domains SET verified_at = inserted_at")

    execute("DROP INDEX IF EXISTS organization_sso_unique_domain_global")

    execute("""
    CREATE UNIQUE INDEX organization_sso_unique_domain_global
    ON organization_sso_domains (lower(domain))
    WHERE verified_at IS NOT NULL
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS organization_sso_unique_domain_global")

    execute(
      "CREATE UNIQUE INDEX organization_sso_unique_domain_global ON organization_sso_domains (lower(domain))"
    )

    alter table(:organization_sso_domains) do
      remove :verification_token
      remove :verified_at
    end
  end
end
