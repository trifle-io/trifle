defmodule Trifle.Organizations.SourceAnnotationsTest do
  use Trifle.DataCase, async: true

  import Trifle.OrganizationsFixtures

  alias Trifle.AccountsFixtures
  alias Trifle.Organizations
  alias Trifle.Organizations.SourceAnnotations
  alias Trifle.Stats.Source

  setup do
    owner = AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: owner})
    owner_membership = Organizations.get_membership_for_user(owner)

    database =
      database_fixture(%{
        organization: organization,
        granularities: ["1m", "1h", "1d"],
        default_granularity: "1h",
        time_zone: "Etc/UTC"
      })

    member = AccountsFixtures.user_fixture()
    {:ok, member_membership} = Organizations.create_membership(organization, member, "member")

    %{
      organization: organization,
      owner_membership: owner_membership,
      member_membership: member_membership,
      source: Source.from_database(database)
    }
  end

  test "create_for_source validates and floors timestamps to the smallest source granularity", %{
    owner_membership: membership,
    source: source
  } do
    assert {:ok, annotation} =
             SourceAnnotations.create_for_source(membership, source, %{
               "at" => "2024-01-01T10:37:45.123456Z",
               "body" => "  Incident started  "
             })

    assert annotation.at == ~U[2024-01-01 10:37:00.000000Z]
    assert annotation.source_granularity == "1m"
    assert annotation.body == "Incident started"
    assert annotation.created_by_user_id == membership.user_id
    assert annotation.updated_by_user_id == membership.user_id
  end

  test "body is required and capped at 2000 characters", %{
    owner_membership: membership,
    source: source
  } do
    assert {:error, changeset} =
             SourceAnnotations.create_for_source(membership, source, %{
               "at" => "2024-01-01T10:37:45Z",
               "body" => ""
             })

    assert "can't be blank" in errors_on(changeset).body

    assert {:error, changeset} =
             SourceAnnotations.create_for_source(membership, source, %{
               "at" => "2024-01-01T10:37:45Z",
               "body" => String.duplicate("a", 2001)
             })

    assert "should be at most 2000 character(s)" in errors_on(changeset).body
  end

  test "all organization members can create update and delete source annotations", %{
    member_membership: membership,
    source: source
  } do
    assert {:ok, annotation} =
             SourceAnnotations.create_for_source(membership, source, %{
               "at" => "2024-01-01T10:00:00Z",
               "body" => "Initial note"
             })

    assert {:ok, updated} =
             SourceAnnotations.update_annotation(membership, annotation, %{
               "body" => "Updated note"
             })

    assert updated.body == "Updated note"
    assert updated.updated_by_user_id == membership.user_id

    assert {:ok, _deleted} = SourceAnnotations.delete_annotation(membership, updated)
    assert SourceAnnotations.get_annotation(membership, annotation.id) == nil
  end

  test "annotations are isolated by organization and source", %{
    owner_membership: membership,
    source: source
  } do
    other_user = AccountsFixtures.user_fixture()

    other_org =
      organization_fixture(%{
        user: other_user,
        name: "other organization #{System.unique_integer([:positive])}"
      })

    other_membership = Organizations.get_membership_for_user(other_user)
    other_database = database_fixture(%{organization: other_org})
    other_source = Source.from_database(other_database)

    assert {:ok, annotation} =
             SourceAnnotations.create_for_source(membership, source, %{
               "at" => "2024-01-01T10:00:00Z",
               "body" => "Scoped note"
             })

    assert [] =
             SourceAnnotations.list_for_source(
               other_membership,
               other_source,
               ~U[2024-01-01 00:00:00Z],
               ~U[2024-01-02 00:00:00Z],
               "1h"
             )

    assert {:error, :unauthorized} =
             SourceAnnotations.update_annotation(other_membership, annotation, %{
               "body" => "Cross-org edit"
             })

    assert {:error, :unauthorized} =
             SourceAnnotations.create_for_source(other_membership, source, %{
               "at" => "2024-01-01T10:00:00Z",
               "body" => "Cross-org create"
             })
  end

  test "grouped_for_source groups annotations by dashboard granularity", %{
    owner_membership: membership,
    source: source
  } do
    {:ok, first} =
      SourceAnnotations.create_for_source(membership, source, %{
        "at" => "2024-01-01T10:05:00Z",
        "body" => "First"
      })

    {:ok, second} =
      SourceAnnotations.create_for_source(membership, source, %{
        "at" => "2024-01-01T10:45:00Z",
        "body" => "Second"
      })

    groups =
      SourceAnnotations.grouped_for_source(
        membership,
        source,
        ~U[2024-01-01 00:00:00Z],
        ~U[2024-01-02 00:00:00Z],
        "1h"
      )

    assert [
             %{
               at: ~U[2024-01-01 10:00:00.000000Z],
               count: 2,
               annotations: annotations
             }
           ] = groups

    assert Enum.map(annotations, & &1.id) == [first.id, second.id]
  end

  test "grouped_for_source coarsens dense annotation groups", %{
    owner_membership: membership,
    source: source
  } do
    start_at = ~U[2024-01-01 00:00:00Z]

    for offset <- 0..260 do
      {:ok, _annotation} =
        SourceAnnotations.create_for_source(membership, source, %{
          "at" => start_at |> DateTime.add(offset * 60, :second) |> DateTime.to_iso8601(),
          "body" => "Note #{offset}"
        })
    end

    groups =
      SourceAnnotations.grouped_for_source(
        membership,
        source,
        start_at,
        DateTime.add(start_at, 261 * 60, :second),
        "1m"
      )

    assert length(groups) < 250
    assert Enum.all?(groups, &(&1.granularity == "1h"))
  end
end
