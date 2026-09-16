defmodule Mix.Tasks.Billing.SetAppSubscriptionExempt do
  use Mix.Task

  @shortdoc "Enable or disable an internal organization's app subscription exemption"
  @moduledoc """
  Enables or disables the app subscription exemption for an existing organization.
  This does not change Stripe subscriptions or waive project subscriptions.

      mix billing.set_app_subscription_exempt ORGANIZATION_UUID true|false
  """

  @impl Mix.Task
  def run(args) do
    {organization_id, exempt} = parse_args!(args)
    Mix.Task.run("app.start")

    case Trifle.Billing.set_app_subscription_exempt(organization_id, exempt) do
      {:ok, entitlement} ->
        organization = Trifle.Organizations.get_organization!(organization_id)

        Mix.shell().info(
          "#{organization.name} (#{organization.id}): app_subscription_exempt=#{exempt}; " <>
            entitlement_status(entitlement)
        )

      {:error, :organization_not_found} ->
        Mix.raise("Organization #{organization_id} was not found")

      {:error, reason} ->
        Mix.raise("Could not update app subscription exemption: #{inspect(reason)}")
    end
  end

  defp parse_args!([organization_id, value]) when value in ["true", "false"] do
    case Ecto.UUID.cast(organization_id) do
      {:ok, id} -> {id, value == "true"}
      :error -> Mix.raise("Organization ID must be a UUID")
    end
  end

  defp parse_args!(_args) do
    Mix.raise("Usage: mix billing.set_app_subscription_exempt ORGANIZATION_UUID true|false")
  end

  defp entitlement_status(nil), do: "billing disabled in this deployment"

  defp entitlement_status(entitlement) do
    "app_tier=#{entitlement.app_tier || "none"}; billing_locked=#{entitlement.billing_locked}"
  end
end
