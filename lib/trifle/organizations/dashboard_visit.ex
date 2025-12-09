defmodule Trifle.Organizations.DashboardVisit do
  use Ecto.Schema

  import Ecto.Changeset

  alias Trifle.Accounts.User
  alias Trifle.Organizations.{Dashboard, Organization}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "dashboard_visits" do
    belongs_to :user, User
    belongs_to :organization, Organization
    belongs_to :dashboard, Dashboard

    field :last_viewed_at, :utc_datetime_usec
    field :view_count, :integer, default: 0

    timestamps()
  end

  def changeset(visit, attrs) do
    visit
    |> cast(attrs, [:user_id, :organization_id, :dashboard_id, :last_viewed_at, :view_count])
    |> validate_required([:user_id, :organization_id, :dashboard_id, :last_viewed_at])
    |> validate_number(:view_count, greater_than_or_equal_to: 0)
    |> unique_constraint(:dashboard_id, name: :dashboard_visits_user_dashboard_index)
  end
end
