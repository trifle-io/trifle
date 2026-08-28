defmodule Trifle.Organizations.DashboardTemplatesTest do
  use Trifle.DataCase

  import Trifle.AccountsFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations
  alias Trifle.Organizations.Dashboard
  alias Trifle.Organizations.DashboardTemplateRef

  setup do
    user = user_fixture()
    organization = organization_fixture(%{user: user})
    membership = Organizations.get_membership_for_user(user)
    database = database_fixture(%{organization: organization})

    %{
      user: user,
      organization: organization,
      membership: membership,
      database: database
    }
  end

  test "encodes polymorphic references and lists grouped available templates", %{
    membership: membership
  } do
    assert {:ok, {:system, "blank"}} = DashboardTemplateRef.parse("system:blank")

    assert {:ok, {:user, "21b3a312-a076-4bac-8d29-d1deaf1b6d7c"}} =
             DashboardTemplateRef.parse("user:21b3a312-a076-4bac-8d29-d1deaf1b6d7c")

    assert {:error, :invalid_template_id} = DashboardTemplateRef.parse("template:blank")

    assert [system_group, user_group] =
             Organizations.list_available_dashboard_templates(membership)

    assert system_group.label == "System templates"

    assert [%{template_id: "system:blank", name: "Blank dashboard", read_only: true}] =
             system_group.templates

    assert user_group.label == "Organization templates"
    assert user_group.templates == []
  end

  test "creates a dashboard linked to an organization template and resolves its effective payload",
       context do
    template = create_template(context, "Shared", %{"grid" => [%{"id" => "one"}]})
    template_id = DashboardTemplateRef.encode(:user, template.id)

    assert {:ok, dashboard} = create_dashboard(context, %{template_id: template_id})
    assert dashboard.template_id == template_id
    assert dashboard.template_type == :user
    assert dashboard.template_name == "Shared"
    assert dashboard.template_version == 1
    assert dashboard.payload == template.payload

    stored = Repo.get!(Dashboard, dashboard.id)
    assert stored.payload == %{}

    fetched = Organizations.get_dashboard_for_membership!(context.membership, dashboard.id)
    assert fetched.payload == template.payload
  end

  test "linked dashboards share payload updates and reject stale versions", context do
    template = create_template(context, "Shared", %{"grid" => []})
    template_id = DashboardTemplateRef.encode(:user, template.id)
    {:ok, first} = create_dashboard(context, %{name: "First", template_id: template_id})
    {:ok, stale} = create_dashboard(context, %{name: "Second", template_id: template_id})
    new_payload = %{"grid" => [%{"id" => "new-widget"}]}

    assert {:ok, updated} =
             Organizations.update_dashboard_for_membership(first, context.membership, %{
               payload: new_payload
             })

    assert updated.payload == new_payload
    assert updated.template_version == 2

    assert {:error, :stale_template} =
             Organizations.update_dashboard_for_membership(stale, context.membership, %{
               payload: %{"grid" => [%{"id" => "stale-widget"}]}
             })

    fresh = Organizations.get_dashboard_for_membership!(context.membership, stale.id)
    assert fresh.payload == new_payload
    assert fresh.template_version == 2
  end

  test "system template payloads are read-only while dashboard metadata remains editable",
       context do
    {:ok, dashboard} = create_dashboard(context, %{template_id: "system:blank"})

    assert dashboard.template_type == :system
    assert dashboard.template_read_only
    assert dashboard.payload == %{"grid" => []}

    assert {:error, :template_read_only} =
             Organizations.update_dashboard_for_membership(dashboard, context.membership, %{
               payload: %{"grid" => [%{"id" => "blocked"}]}
             })

    assert {:ok, renamed} =
             Organizations.update_dashboard_for_membership(dashboard, context.membership, %{
               name: "Renamed locally"
             })

    assert renamed.name == "Renamed locally"
    assert renamed.payload == %{"grid" => []}
  end

  test "converts a local dashboard into a template and detaches with a payload snapshot",
       context do
    original_payload = %{"grid" => [%{"id" => "original"}]}
    {:ok, dashboard} = create_dashboard(context, %{payload: original_payload})

    assert {:ok, %{template: template, dashboard: converted}} =
             Organizations.convert_dashboard_to_template(
               context.user,
               context.membership,
               dashboard,
               %{name: "Converted template"}
             )

    assert template.payload == original_payload
    assert converted.template_id == DashboardTemplateRef.encode(:user, template.id)
    assert converted.payload == original_payload

    assert {:ok, detached} =
             Organizations.detach_dashboard_template(converted, context.membership)

    assert detached.template_id == nil
    assert detached.payload == original_payload

    assert {:ok, _template} =
             Organizations.update_dashboard_template(
               template,
               context.user,
               context.membership,
               %{payload: %{"grid" => [%{"id" => "later"}]}, template_version: 1}
             )

    reloaded = Organizations.get_dashboard_for_membership!(context.membership, detached.id)
    assert reloaded.template_id == nil
    assert reloaded.payload == original_payload
  end

  test "blocks deleting templates that are still linked", context do
    template = create_template(context, "In use", %{"grid" => []})

    {:ok, _dashboard} =
      create_dashboard(context, %{template_id: DashboardTemplateRef.encode(:user, template.id)})

    assert {:error, :template_in_use} =
             Organizations.delete_dashboard_template(
               template,
               context.user,
               context.membership
             )
  end

  test "does not allow a dashboard to link a template from another organization", context do
    other_user = user_fixture()
    unique = System.unique_integer([:positive])

    _other_organization =
      organization_fixture(%{
        user: other_user,
        name: "Other organization #{unique}",
        slug: "other-organization-#{unique}"
      })

    other_membership = Organizations.get_membership_for_user(other_user)

    {:ok, other_template} =
      Organizations.create_dashboard_template(other_user, other_membership, %{
        name: "Private to another organization",
        payload: %{"grid" => []}
      })

    assert {:error, :template_not_found} =
             create_dashboard(context, %{
               template_id: DashboardTemplateRef.encode(:user, other_template.id)
             })
  end

  defp create_template(context, name, payload) do
    {:ok, template} =
      Organizations.create_dashboard_template(context.user, context.membership, %{
        name: name,
        payload: payload
      })

    template
  end

  defp create_dashboard(context, attrs) do
    unique = System.unique_integer([:positive])

    base_attrs = %{
      name: "Dashboard #{unique}",
      key: "dashboard.#{unique}",
      source_type: "database",
      source_id: context.database.id,
      database_id: context.database.id,
      default_timeframe: "24h",
      default_granularity: "1h",
      payload: %{"grid" => []}
    }

    Organizations.create_dashboard_for_membership(
      context.user,
      context.membership,
      Map.merge(base_attrs, attrs)
    )
  end
end
