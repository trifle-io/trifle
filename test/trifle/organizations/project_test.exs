defmodule Trifle.Organizations.ProjectTest do
  use ExUnit.Case, async: true

  alias Trifle.Organizations.Project

  test "billing_changeset casts billing fields" do
    changeset =
      Project.billing_changeset(%Project{}, %{billing_required: false, billing_state: "active"})

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :billing_required) == false
    assert Ecto.Changeset.get_change(changeset, :billing_state) == "active"
  end

  test "billing_changeset validates billing_state inclusion" do
    changeset =
      Project.billing_changeset(%Project{}, %{
        billing_required: true,
        billing_state: "suspended"
      })

    refute changeset.valid?
    assert {"is invalid", _opts} = changeset.errors[:billing_state]
  end

  test "changeset validates retention choices" do
    changeset =
      Project.changeset(%Project{}, %{
        name: "Retention Test",
        time_zone: "Etc/UTC",
        beginning_of_week: 1,
        granularities: ["1m"],
        organization_id: Ecto.UUID.generate(),
        expire_after: 3_600
      })

    refute changeset.valid?
    assert {"is invalid", _opts} = changeset.errors[:expire_after]
  end

  test "changeset prevents retention updates for existing projects" do
    project = %Project{
      id: Ecto.UUID.generate(),
      name: "Retention Locked",
      time_zone: "Etc/UTC",
      beginning_of_week: 1,
      granularities: ["1m"],
      organization_id: Ecto.UUID.generate(),
      expire_after: Project.basic_retention_seconds()
    }

    changeset =
      Project.changeset(project, %{expire_after: Project.extended_retention_seconds()})

    refute changeset.valid?
    assert {"cannot be changed after project creation", _opts} = changeset.errors[:expire_after]
  end
end
