defmodule Trifle.Billing.SystemNotificationsTest do
  use Trifle.DataCase, async: false

  import Swoosh.TestAssertions
  import Trifle.AccountsFixtures
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Accounts
  alias Trifle.Billing.Jobs.ProcessStripeEvent
  alias Trifle.Billing.WebhookEvent
  alias Trifle.Repo

  setup do
    admin = user_fixture(%{email: "billing-admin@example.com"})
    {:ok, admin} = Accounts.update_user_admin_status(admin.id, true)
    organization = organization_fixture(%{user: admin, name: "Acme Billing"})
    project = project_fixture(%{user: admin, organization: organization, name: "Events"})

    assert_email_sent(subject: "[Trifle System] Project created: Events")

    %{admin: admin, organization: organization, project: project}
  end

  test "subscription creation notifies for organization and project scopes", context do
    process_subscription_event(
      "customer.subscription.created",
      subscription_payload(context.organization.id, "app", nil, "sub_app_created")
    )

    assert_email_sent(
      to: context.admin.email,
      subject: "[Trifle System] Subscription created: Acme Billing"
    )

    process_subscription_event(
      "customer.subscription.created",
      subscription_payload(
        context.organization.id,
        "project",
        context.project.id,
        "sub_project_created"
      )
    )

    assert_email_sent(
      to: context.admin.email,
      subject: "[Trifle System] Subscription created: Events"
    )
  end

  test "scheduled and effective cancellation notify for both scopes", context do
    app_subscription =
      app_subscription_fixture(context.organization, %{
        stripe_subscription_id: "sub_app_cancel",
        cancel_at_period_end: false
      })

    project_subscription =
      project_subscription_fixture(context.project, %{
        stripe_subscription_id: "sub_project_cancel",
        cancel_at_period_end: false
      })

    for {scope, scope_id, subscription, expected_name} <- [
          {"app", nil, app_subscription, "Acme Billing"},
          {"project", context.project.id, project_subscription, "Events"}
        ] do
      process_subscription_event(
        "customer.subscription.updated",
        subscription_payload(
          context.organization.id,
          scope,
          scope_id,
          subscription.stripe_subscription_id,
          %{"cancel_at_period_end" => true}
        )
      )

      assert_email_sent(
        to: context.admin.email,
        subject: "[Trifle System] Subscription cancellation scheduled: #{expected_name}"
      )

      process_subscription_event(
        "customer.subscription.deleted",
        subscription_payload(
          context.organization.id,
          scope,
          scope_id,
          subscription.stripe_subscription_id,
          %{"status" => "canceled", "cancel_at_period_end" => false}
        )
      )

      assert_email_sent(
        to: context.admin.email,
        subject: "[Trifle System] Subscription cancelled: #{expected_name}"
      )
    end
  end

  test "ordinary updates and repeated processed events do not duplicate notifications", context do
    subscription =
      app_subscription_fixture(context.organization, %{
        stripe_subscription_id: "sub_app_ordinary",
        cancel_at_period_end: false
      })

    event =
      process_subscription_event(
        "customer.subscription.updated",
        subscription_payload(
          context.organization.id,
          "app",
          nil,
          subscription.stripe_subscription_id
        )
      )

    refute_email_sent()
    assert :ok = ProcessStripeEvent.perform(%Oban.Job{args: %{"webhook_event_id" => event.id}})
    refute_email_sent()
  end

  defp process_subscription_event(event_type, subscription_payload) do
    event =
      Repo.insert!(%WebhookEvent{
        stripe_event_id: "evt_#{Ecto.UUID.generate()}",
        event_type: event_type,
        payload: %{
          "type" => event_type,
          "data" => %{"object" => subscription_payload}
        }
      })

    assert :ok = ProcessStripeEvent.perform(%Oban.Job{args: %{"webhook_event_id" => event.id}})
    Repo.get!(WebhookEvent, event.id)
  end

  defp subscription_payload(
         organization_id,
         scope_type,
         scope_id,
         subscription_id,
         overrides \\ %{}
       ) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    metadata =
      %{
        "organization_id" => organization_id,
        "scope_type" => scope_type
      }
      |> maybe_put_scope_id(scope_id)

    Map.merge(
      %{
        "id" => subscription_id,
        "customer" => "cus_test",
        "status" => "active",
        "cancel_at_period_end" => false,
        "current_period_start" => now,
        "current_period_end" => now + 2_592_000,
        "metadata" => metadata,
        "items" => %{
          "data" => [
            %{
              "id" => "si_#{subscription_id}",
              "price" => %{
                "id" => "price_test",
                "recurring" => %{"interval" => "month"}
              }
            }
          ]
        }
      },
      overrides
    )
  end

  defp maybe_put_scope_id(metadata, nil), do: metadata
  defp maybe_put_scope_id(metadata, scope_id), do: Map.put(metadata, "scope_id", scope_id)
end
