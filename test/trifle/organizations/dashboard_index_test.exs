defmodule Trifle.Organizations.DashboardIndexTest do
  use Trifle.DataCase

  import Trifle.AccountsFixtures
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations

  setup do
    owner = user_fixture()
    organization = organization_fixture(%{user: owner})
    membership = Organizations.get_membership_for_user(owner)
    app_entitlement_fixture(organization)
    database = database_fixture(%{organization: organization})

    %{owner: owner, organization: organization, membership: membership, database: database}
  end

  defp group!(membership, name, parent \\ nil) do
    {:ok, group} =
      Organizations.create_dashboard_group_for_membership(membership, %{
        "name" => name,
        "parent_group_id" => parent && parent.id
      })

    group
  end

  defp dashboard!(user, membership, database, name, attrs \\ %{}) do
    {:ok, dashboard} =
      Organizations.create_dashboard_for_membership(
        user,
        membership,
        Map.merge(
          %{
            "name" => name,
            "key" => "metric",
            "source_type" => "database",
            "source_id" => database.id
          },
          attrs
        )
      )

    dashboard
  end

  defp names(dashboards), do: dashboards |> Enum.map(& &1.name) |> Enum.sort()

  test "assembles nested groups and their dashboards", ctx do
    %{owner: owner, membership: membership, database: database} = ctx

    ops = group!(membership, "Ops")
    infra = group!(membership, "Infra", ops)
    sales = group!(membership, "Sales")

    dashboard!(owner, membership, database, "Loose")
    dashboard!(owner, membership, database, "Ops overview", %{"group_id" => ops.id})
    dashboard!(owner, membership, database, "Hosts", %{"group_id" => infra.id})
    dashboard!(owner, membership, database, "Disks", %{"group_id" => infra.id})

    index = Organizations.dashboard_index_for_membership(owner, membership)

    assert index.dashboards_count == 4
    assert index.dashboard_groups_count == 3
    assert names(index.ungrouped_dashboards) == ["Loose"]

    assert [ops_node, sales_node] = Enum.sort_by(index.groups_tree, & &1.group.name)
    assert ops_node.group.id == ops.id
    assert names(ops_node.dashboards) == ["Ops overview"]
    assert [infra_node] = ops_node.children
    assert infra_node.group.id == infra.id
    assert names(infra_node.dashboards) == ["Disks", "Hosts"]
    assert infra_node.children == []

    assert sales_node.group.id == sales.id
    assert sales_node.children == []
    assert sales_node.dashboards == []
  end

  test "matches the per-group listing it replaces", ctx do
    %{owner: owner, membership: membership, database: database} = ctx

    ops = group!(membership, "Ops")
    dashboard!(owner, membership, database, "A", %{"group_id" => ops.id})
    dashboard!(owner, membership, database, "B")

    index = Organizations.dashboard_index_for_membership(owner, membership)
    [ops_node] = index.groups_tree

    ids = fn dashboards -> Enum.map(dashboards, & &1.id) end

    assert ids.(ops_node.dashboards) ==
             ids.(Organizations.list_dashboards_for_membership(owner, membership, ops.id))

    assert ids.(index.ungrouped_dashboards) ==
             ids.(Organizations.list_dashboards_for_membership(owner, membership, nil))

    assert index.dashboards_count ==
             Organizations.count_dashboards_for_membership(owner, membership)

    assert Organizations.list_dashboard_tree_for_membership(owner, membership) ==
             index.groups_tree
  end

  test "plain members only see their own and visible dashboards", ctx do
    %{owner: owner, organization: organization, membership: membership, database: database} = ctx

    member = user_fixture()
    {:ok, member_membership} = Organizations.create_membership(organization, member, "member")

    dashboard!(owner, membership, database, "Private", %{"visibility" => false})
    dashboard!(owner, membership, database, "Shared", %{"visibility" => true})

    index = Organizations.dashboard_index_for_membership(member, member_membership)

    assert names(index.ungrouped_dashboards) == ["Shared"]
    assert index.dashboards_count == 1
  end

  test "does not leak other organizations", ctx do
    %{owner: owner, membership: membership} = ctx

    stranger = user_fixture()
    other_org = organization_fixture(%{user: stranger, name: "Other Org"})
    # Needed in SaaS mode, where a source is only usable with an active subscription.
    app_entitlement_fixture(other_org)
    other_membership = Organizations.get_membership_for_user(stranger)
    other_db = database_fixture(%{organization: other_org})
    group!(other_membership, "Theirs")
    dashboard!(stranger, other_membership, other_db, "Their dashboard")

    index = Organizations.dashboard_index_for_membership(owner, membership)

    assert index.groups_tree == []
    assert index.ungrouped_dashboards == []
    assert index.dashboards_count == 0
    assert index.dashboard_groups_count == 0
  end
end
