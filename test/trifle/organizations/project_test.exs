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
end
