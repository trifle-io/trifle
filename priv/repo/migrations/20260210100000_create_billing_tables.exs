defmodule Trifle.Repo.Migrations.CreateBillingTables do
  use Ecto.Migration

  def change do
    create table(:billing_customers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :stripe_customer_id, :string, null: false
      add :email, :string
      add :name, :string
      add :default_payment_method_last4, :string
      add :default_payment_method_brand, :string
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:billing_customers, [:organization_id])
    create unique_index(:billing_customers, [:stripe_customer_id])

    create table(:billing_plans, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :nilify_all)

      add :name, :string, null: false
      add :scope_type, :string, null: false
      add :tier_key, :string, null: false
      add :interval, :string, null: false
      add :stripe_price_id, :string, null: false
      add :currency, :string, null: false, default: "usd"
      add :amount_cents, :integer
      add :seat_limit, :integer
      add :hard_limit, :bigint
      add :retention_add_on, :boolean, null: false, default: false
      add :founder_offer, :boolean, null: false, default: false
      add :active, :boolean, null: false, default: true
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create constraint(:billing_plans, :billing_plans_scope_type_check,
             check: "scope_type IN ('app', 'project')"
           )

    create unique_index(:billing_plans, [:stripe_price_id],
             name: :billing_plans_stripe_price_id_unique
           )

    create index(:billing_plans, [:scope_type, :tier_key, :active],
             name: :billing_plans_scope_type_tier_key_active_index
           )

    create index(:billing_plans, [:organization_id, :scope_type, :tier_key, :active],
             name: :billing_plans_organization_id_scope_type_tier_key_active_index
           )

    create unique_index(
             :billing_plans,
             [:scope_type, :tier_key, :interval, :retention_add_on, :founder_offer],
             name: :billing_plans_active_global_unique,
             where: "active = true AND organization_id IS NULL"
           )

    create unique_index(
             :billing_plans,
             [
               :organization_id,
               :scope_type,
               :tier_key,
               :interval,
               :retention_add_on,
               :founder_offer
             ],
             name: :billing_plans_active_org_unique,
             where: "active = true AND organization_id IS NOT NULL"
           )

    create table(:billing_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :scope_type, :string, null: false
      add :scope_id, :binary_id
      add :stripe_subscription_id, :string, null: false
      add :stripe_customer_id, :string
      add :stripe_price_id, :string
      add :status, :string
      add :interval, :string
      add :current_period_start, :utc_datetime
      add :current_period_end, :utc_datetime
      add :cancel_at_period_end, :boolean, null: false, default: false
      add :grace_until, :utc_datetime
      add :founder_price, :boolean, null: false, default: false
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create constraint(:billing_subscriptions, :billing_subscriptions_scope_type_check,
             check: "scope_type IN ('app', 'project')"
           )

    create unique_index(:billing_subscriptions, [:stripe_subscription_id])
    create index(:billing_subscriptions, [:organization_id])
    create index(:billing_subscriptions, [:scope_type, :scope_id])

    create unique_index(:billing_subscriptions, [:organization_id],
             name: :billing_subscriptions_org_app_unique,
             where: "scope_type = 'app'"
           )

    create unique_index(:billing_subscriptions, [:organization_id, :scope_id],
             name: :billing_subscriptions_org_project_unique,
             where: "scope_type = 'project'"
           )

    create table(:billing_entitlements, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :app_tier, :string
      add :seat_limit, :integer
      add :projects_enabled, :boolean, null: false, default: false
      add :billing_locked, :boolean, null: false, default: false
      add :lock_reason, :string
      add :founder_offer_locked, :boolean, null: false, default: false
      add :effective_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:billing_entitlements, [:organization_id])

    create table(:billing_webhook_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :stripe_event_id, :string, null: false
      add :event_type, :string, null: false
      add :status, :string, null: false, default: "received"
      add :processed_at, :utc_datetime
      add :error, :text
      add :payload, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:billing_webhook_events, [:stripe_event_id])

    create table(:billing_founder_claims, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :slot_number, :integer, null: false
      add :claimed_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:billing_founder_claims, [:organization_id])
    create unique_index(:billing_founder_claims, [:slot_number])
  end
end
