# Internal organization billing

An operator can exempt a dedicated internal organization from the SaaS app
subscription requirement. Its members can create and use database sources under
the existing organization permissions. This includes a manually configured source
for Trifle's internal observability data and any additional database sources.

The exemption is independent of global Admin status and applies to the entire
organization. It does not provision a source automatically in SaaS, waive hosted
project subscriptions, or create, cancel, or modify Stripe subscriptions. Keep
paid billing tests in a separate organization.

## Enable or disable

Deploy and run database migrations first. Find the intended organization's UUID
in the admin interface or through a release console, then run:

```sh
docker compose exec -T app mix billing.set_app_subscription_exempt ORGANIZATION_UUID true
```

The command reports the organization's name, UUID, exemption flag, and resulting
entitlement. Repeating the command is safe. To restore normal subscription checks:

```sh
docker compose exec -T app mix billing.set_app_subscription_exempt ORGANIZATION_UUID false
```

For a deployed release without Mix, use its remote console:

```elixir
Trifle.Billing.set_app_subscription_exempt("ORGANIZATION_UUID", true)
# Restore normal billing:
Trifle.Billing.set_app_subscription_exempt("ORGANIZATION_UUID", false)
```

The function returns `{:ok, entitlement}` or `{:error, reason}`. Billing-disabled
deployments return `{:ok, nil}` while still storing the flag.

Enabling the exemption grants an internal app entitlement with unlimited seats.
Refreshes and Stripe subscription events preserve it. Disabling it derives access
from the organization's real subscription, or locks access if none exists.
Existing subscriptions continue their normal billing lifecycle while exempt.

The flag and entitlement update together. Entitlement cache invalidation is local
to the process's node; other running nodes pick up changes within the configured
cache TTL (60 seconds by default). Reload the billing page after this interval to
see “Internal — subscription exempt”, then add the observability database through
the normal database form. No customer-facing control can change the flag.
