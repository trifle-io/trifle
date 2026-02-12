defmodule Trifle.Billing.ProjectUsageTest do
  use ExUnit.Case, async: true

  alias Trifle.Billing.ProjectUsage

  test "requires period_end to be after period_start" do
    start_at = ~U[2026-02-01 00:00:00Z]

    attrs = %{
      project_id: Ecto.UUID.generate(),
      period_start: start_at,
      period_end: start_at,
      events_count: 0
    }

    changeset = ProjectUsage.changeset(%ProjectUsage{}, attrs)

    refute changeset.valid?
    assert {"must be after period_start", _opts} = changeset.errors[:period_end]
  end

  test "accepts a valid period range" do
    attrs = %{
      project_id: Ecto.UUID.generate(),
      period_start: ~U[2026-02-01 00:00:00Z],
      period_end: ~U[2026-02-01 01:00:00Z],
      events_count: 0
    }

    changeset = ProjectUsage.changeset(%ProjectUsage{}, attrs)

    assert changeset.valid?
  end
end
