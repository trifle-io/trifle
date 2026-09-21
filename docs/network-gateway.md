# Tailscale network gateway

The gateway replaces Private Connector's polling jobs with persistent TCP streams. One gateway process runs independent `tsnet.Server` instances for named organization connections. App replicas connect to that gateway over mutual TLS; each node joins its customer's tailnet. Customers do not deploy a Trifle gateway. They need Tailscale on the database/storage host, or a subnet router that can reach it.

```text
App replicas -- mTLS --> shared network gateway
                          ├─ organization A / connection A → tailnet A → database / S3
                          └─ organization B / connection B → tailnet B → database / S3
```

Identical private IPs and DNS names in different tailnets are independent. Queries do not wait for a poll interval. Actual latency depends on network distance, database performance and whether Tailscale can establish a direct connection or uses a relay.

## How traffic reaches the gateway

Each database source selects a named organization connection; trace storage can select its own connection. All App replicas use the same private `TRIFLE_GATEWAY_URL`, which Helm sets to `https://<release>-network-gateway:8443`. The Kubernetes Service selects the single gateway pod. Configuration, status checks, route registration and TCP streams all go to that endpoint over mTLS.

Inside the gateway, the organization ID and connection ID select an independent Tailscale node. A stream must also match an App-registered source, destination and configuration version. The gateway uses that node's tailnet to dial the database or storage endpoint. A customer's internal IP is therefore resolved in the selected connection, even when another customer uses the same IP.

The initial deployment deliberately has one gateway. Adding capacity later requires a persistent connection-to-gateway assignment and a stable endpoint and state volume for each gateway. App must send both control requests and streams to the assigned gateway. Increasing replicas behind the current Service would distribute requests among nodes that do not own the same connections; session affinity does not provide the required ownership. Moving a connection will need a controlled handoff that stops its old node before starting the new owner.

## Enroll a customer network

1. In Tailscale, create a dedicated tag, for example `tag:trifle`, and grant it only the database and storage ports needed. Keep existing authentication and database TLS enabled where appropriate.
2. Create a **non-ephemeral auth key**, ideally single-use and preapproved, with that tag. Trifle accepts `tskey-auth-*`. API access tokens and OAuth client secrets are not enrollment keys. An operator can use Tailscale's API to generate an auth key, then supply that key here.
3. In **Organization → Connections**, add a name and auth key. If device approval or Tailnet Lock is enabled, complete the required approval/signing in Tailscale.
4. Select **Tailscale** on a database source, choose this connection and enter its Tailscale IP, MagicDNS name, or a literal IP behind an approved subnet router. Use the database's normal credentials and port.
5. For private S3/MinIO trace payloads, separately select the **Storage network** and enter the explicit HTTP(S) endpoint, bucket and credentials. The database index and storage can use different connections.

The auth key is encrypted in App's database until the node reports enrolled and Running, then removed. A background job refreshes connection health every minute, including when the browser is closed. **Refresh status** checks immediately. Gateway node state persists independently of the bootstrap key.

[Tailscale auth keys](https://tailscale.com/docs/features/access-control/auth-keys), [grants](https://tailscale.com/docs/features/access-control/grants), [subnet routers](https://tailscale.com/docs/features/subnet-routers), and [tsnet](https://tailscale.com/docs/features/tsnet) describe the underlying Tailscale behavior.

## Supported destinations

| Resource | Support |
| --- | --- |
| Stats | PostgreSQL, MySQL, MongoDB, Redis |
| Trace index | PostgreSQL, MongoDB |
| Trace payloads and attachments | S3/MinIO HTTP(S), with a separately selected network |
| Filesystem / SQLite | Local to App; Tailscale does not expose remote files |

MongoDB uses a single configured endpoint over Tailscale. Replica-set discovery, SRV discovery, Redis Cluster/Sentinel and transparent failover between advertised endpoints are not supported. Use a stable endpoint that can serve the required reads/writes. Names resolve only from the selected node's MagicDNS peer map. Custom/split DNS names are not resolved; use the subnet destination's literal IP. Exit-node default routes and arbitrary public destinations are rejected.

Database TLS verifies the original database hostname, rather than the loopback forwarding address. Private S3 retains its original Host header, TLS hostname and AWS signature. S3 HTTP pooling is disabled for private connections to prevent reuse across organizations. Redirects to another destination are rejected by the restricted SOCKS endpoint. Private CAs for database/storage certificates must be trusted by the App runtime.

## Deploy with Docker Compose

Build from this checkout before using an unreleased version:

```sh
docker build -f .devops/docker/network-gateway/Dockerfile \
  -t trifle/network-gateway:local network-gateway
```

On the deployment host, create certificates outside the repository and save a stable encryption key in your secret manager:

```sh
bash .devops/scripts/create-gateway-certs.sh /absolute/private/gateway-certs network-gateway
openssl rand -base64 32
```

Set `TRIFLE_GATEWAY_CERTS_DIR` to that directory, `TRIFLE_GATEWAY_STATE_KEY` to the generated key, and `TRIFLE_GATEWAY_IMAGE_TAG` to `local` (or an explicitly published release tag). Merge the optional Compose override into your deployment:

```sh
docker compose -f docker-compose.yml -f .devops/docker/network-gateway/compose.yaml up -d
```

The override expects an `app` service. The development Compose file mounts source; production should use your release image. Keep the gateway on the private container network. Do not publish port 8443. Only the App needs client certificates. Neither runtime receives the CA signing key. Generated runtime certificates expire after one year; replace them before expiry and restart both services.

## Deploy with Helm

The base `values.yaml` sets `networkGateway.enabled: false`: self-hosted installations create no gateway or gateway credentials by default. Operators can enable it when private tailnet access is needed. SaaS deployments use `values-saas.yaml`, which sets `app.deploymentMode: saas` and enables one gateway. The deployment mode alone does not override an explicit gateway setting.

```sh
helm upgrade --install trifle .devops/kubernetes/helm/trifle \
  --namespace trifle --create-namespace \
  -f .devops/kubernetes/helm/trifle/values-saas.yaml \
  -f /absolute/private/environment-values.yaml
```

Use the same published release tag for `image.tag` and `networkGateway.image.tag` in your environment values. Configure `networkGateway.storageClass` if the cluster has no default storage class, and use `networkGateway.nodeSelector`/`tolerations`/`affinity` if storage is restricted to particular nodes. Registry credentials in `imagePullSecrets` apply to both App and gateway images. App replicas and autoscaling never increase the gateway replica count.

With all three Secret names left empty, Helm generates a random 32-byte state encryption key and a private CA with separate server/client certificates. It creates `<release>-network-gateway-state`, `-server` and `-client` Secrets, mounts only each runtime's own credentials, and discards the CA signing key. Server certificates cover the private Service DNS name. Names are shortened for long release names.

On subsequent installs/upgrades, Helm's [lookup](https://helm.sh/docs/chart_template_guide/functions_and_pipelines/#using-the-lookup-function) reads and reuses existing credentials. The deployment identity needs permission to read Secrets and PVCs in the namespace. Missing credentials alongside existing Secrets or a PVC fail the deployment: restore the original Secrets rather than generating a different state key. The three Secrets and gateway PVC carry `helm.sh/resource-policy: keep`, so disabling the gateway or uninstalling the release retains them; final removal requires deliberate cleanup. Back up the volume and its encryption key separately.

Generated runtime certificates expire after one year and are not automatically renewed. Before expiry, generate a replacement CA/server/client set, update both TLS Secrets during a maintenance window, and restart App and gateway. Preserve the state Secret unchanged. The certificate script below can generate that replacement set.

For GitOps controllers or workflows that repeatedly run offline `helm template`, use externally managed Secrets instead. Offline rendering cannot look up previous credentials and generates new ones each time; do not apply repeated offline renders in managed mode. Use `--dry-run=server` to check the reuse behavior against a cluster.

### Externally managed credentials

Set all three Secret references to bypass Helm credential generation. Create certificates for the actual service DNS name (for release `trifle`, usually `trifle-network-gateway`) using `.devops/scripts/create-gateway-certs.sh`. Create three secrets in the App namespace:

```sh
kubectl -n trifle create secret generic gateway-server-tls \
  --from-file=ca.crt=/absolute/private/gateway-certs/ca.crt \
  --from-file=server.crt=/absolute/private/gateway-certs/server.crt \
  --from-file=server.key=/absolute/private/gateway-certs/server.key
kubectl -n trifle create secret generic gateway-client-tls \
  --from-file=ca.crt=/absolute/private/gateway-certs/ca.crt \
  --from-file=client.crt=/absolute/private/gateway-certs/client.crt \
  --from-file=client.key=/absolute/private/gateway-certs/client.key
# state-key.txt contains the saved base64 key, without a trailing newline.
kubectl -n trifle create secret generic gateway-state \
  --from-file=state-key=/absolute/private/state-key.txt
```

```yaml
networkGateway:
  enabled: true
  image:
    repository: trifle/network-gateway
    tag: "<published-release-tag>"
  stateKeySecret: gateway-state
  serverTLSSecret: gateway-server-tls
  clientTLSSecret: gateway-client-tls
  storageSize: 1Gi
```

The chart creates a private service, ingress policy, one persistent gateway replica and a `Recreate` deployment strategy. App autoscaling remains independent. No TUN device, privileged container, host network or NET_ADMIN capability is required. Outbound access to Tailscale coordination/relay services and UDP connectivity are needed; restrictive network policies may force relay use. The provided ingress policy permits only App-to-gateway TCP traffic. Capacity depends on the number of enrolled nodes and streams; monitor memory and load before increasing tenant counts.

## Environment reference

| Service | Variable | Purpose |
| --- | --- | --- |
| App | `TRIFLE_GATEWAY_URL` | Private HTTPS URL, such as `https://network-gateway:8443` |
| App | `TRIFLE_GATEWAY_CA_FILE` | Dedicated gateway CA certificate |
| App | `TRIFLE_GATEWAY_CERT_FILE` / `TRIFLE_GATEWAY_KEY_FILE` | App client certificate/key |
| Gateway | `TRIFLE_GATEWAY_STATE_KEY` | Stable base64-encoded 32-byte AES key |
| Gateway | `TRIFLE_GATEWAY_STATE_DIR` | Durable state directory; default `/data` |
| Gateway | `TRIFLE_GATEWAY_ADDR` | Private listen address; default `:8443` |
| Gateway | `TRIFLE_GATEWAY_CLIENT_CA` | Dedicated CA for authorized App clients |
| Gateway | `TRIFLE_GATEWAY_TLS_CERT` / `TRIFLE_GATEWAY_TLS_KEY` | Server certificate/key matching the App URL |

Do not set process-wide Tailscale authentication variables. Enrollment belongs to individual connections. Back up `/data` and its encryption key separately. Losing either requires reauthorization. The gateway refuses concurrent ownership of its state directory. Never run another gateway against copied live state; two processes must not use the same Tailscale node identities.

## Lifecycle and operations

- **Disconnect** invalidates active streams and deletes the local node identity. It succeeds only after the gateway acknowledges. Remove the old device from the Tailscale admin console as well.
- **Reauthorize** uses a fresh key and a higher configuration generation to enroll a new device. Update grants/approval if required, and remove the previous device from Tailscale.
- **Delete** requires reassigning sources first and disables the gateway node before deleting the App record. Disabled generation tombstones remain encrypted in gateway state to reject stale requests.
- Restarting the gateway restores nodes from encrypted state without bootstrap keys. Existing sockets close; database pools reconnect on subsequent queries. Routes are registered again by App as needed. This version has no gateway HA.
- The private `/v1/status` response reports Tailscale state and active stream count. Logs include connection/source IDs and dial duration, never SQL, credentials, trace bodies or enrollment URLs. The process allows at most 4096 concurrent streams globally and 256 per connection. Health probes check the listener; source checks determine whether a customer destination is reachable.
- A denied/unavailable route fails closed. Check device approval, expiry, grants, subnet approval, database listener and TLS hostname. Trifle does not retry a private destination through the App's normal network.

## Breaking upgrade from Private Connector

Stop App workers/replicas before applying migration `20260918150000_replace_connectors_with_network_connections`. Take a database backup first. Deploy the gateway and new App version, then run migrations with the release's usual migration command.

The migration retains source IDs, names, hosts, credentials and settings. Former connector sources become `unconfigured`, display a setup message and cannot query until a connection method is explicitly selected. Connector registrations, tokens and queued/completed jobs are removed. The old endpoints return HTTP 410. Stop and remove customer `trifle/connector` containers. There is no mixed-version rollout or down migration; rollback requires restoring the backup and previous images.

## Verification

Run App tests and `mix format` inside the app container. Gateway tests (`go test -race ./...` in `network-gateway`) exercise encrypted state, restart, overlapping tailnet addresses, destination authorization, mutual TLS and stream cancellation with simulated nodes. App transport tests send a real PostgreSQL query and a signed S3 request through an mTLS stream fixture. A release still needs a real-tailnet smoke test: enroll, query Stats, browse a trace/attachment, restart the gateway and confirm reconnect, then revoke grants and confirm access fails.

Chart checks run in CI and can be run inside the App container with Helm on PATH (or `HELM_BIN` set): `ruby .devops/kubernetes/helm/test_network_gateway.rb`. They cover disabled self-hosted defaults, SaaS routing and a single replica, valid mTLS credentials, and preservation or failure during upgrades against a simulated read-only Kubernetes API.

OAuth enrollment and gateway HA are future work. The initial SaaS and self-hosted flow both use customer-supplied auth keys.
