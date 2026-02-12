defmodule Trifle.Billing.ProjectUsage do
  use Ecto.Schema
  import Ecto.Changeset

  alias Trifle.Organizations.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "project_billing_usage" do
    field :period_start, :utc_datetime
    field :period_end, :utc_datetime
    field :events_count, :integer, default: 0
    field :tier_key, :string
    field :hard_limit, :integer
    field :locked_at, :utc_datetime

    belongs_to :project, Project

    timestamps()
  end

  def changeset(usage, attrs) do
    usage
    |> cast(attrs, [
      :project_id,
      :period_start,
      :period_end,
      :events_count,
      :tier_key,
      :hard_limit,
      :locked_at
    ])
    |> validate_required([:project_id, :period_start, :period_end, :events_count])
    |> validate_number(:events_count, greater_than_or_equal_to: 0)
    |> validate_period_range()
    |> unique_constraint(:project_period, name: :project_billing_usage_project_period_unique)
  end

  defp validate_period_range(changeset) do
    period_start = get_field(changeset, :period_start)
    period_end = get_field(changeset, :period_end)

    case {period_start, period_end} do
      {%DateTime{} = start_at, %DateTime{} = end_at} ->
        case DateTime.compare(end_at, start_at) do
          :gt -> changeset
          _ -> add_error(changeset, :period_end, "must be after period_start")
        end

      _ ->
        changeset
    end
  end
end
