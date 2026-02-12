defmodule Trifle.Repo.Migrations.CreateProjectBillingUsage do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :billing_required, :boolean, null: false, default: true
      add :billing_state, :string, null: false, default: "pending_checkout"
    end

    create constraint(:projects, :projects_billing_state_check,
             check: "billing_state IN ('pending_checkout', 'active', 'locked')"
           )

    create table(:project_billing_usage, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :period_start, :utc_datetime, null: false
      add :period_end, :utc_datetime, null: false
      add :events_count, :bigint, null: false, default: 0
      add :tier_key, :string
      add :hard_limit, :bigint
      add :locked_at, :utc_datetime

      timestamps()
    end

    create index(:project_billing_usage, [:project_id])

    create unique_index(:project_billing_usage, [:project_id, :period_start],
             name: :project_billing_usage_project_period_unique
           )

    create constraint(:project_billing_usage, :project_billing_usage_period_range_check,
             check: "period_end > period_start"
           )

    create constraint(:project_billing_usage, :project_billing_usage_hard_limit_check,
             check: "hard_limit IS NULL OR hard_limit >= 0"
           )

    create constraint(:project_billing_usage, :project_billing_usage_events_count_check,
             check: "events_count >= 0"
           )
  end
end
