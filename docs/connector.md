# Trifle Private Connector

The Trifle Private Connector is a small Dockerized connector for databases that are not reachable from Trifle Cloud by IP allowlist or SSH tunnel. It runs inside the customer's network and opens outbound HTTPS connections to Trifle Cloud, so private databases can stay off the public internet.

The Docker image polls the Trifle Cloud control plane over the `/api/v1/connectors/*` endpoints described below. Create a private connector from Organization > Connectors to get the one-time bearer token and Docker command.

## Security Model

- Outbound-only: the connector does not require inbound access from Trifle Cloud.
- Token-authenticated: every control-plane request uses `TRIFLE_CONNECTOR_TOKEN` as a bearer token.
- Least-reachability: network jobs are constrained by `TRIFLE_CONNECTOR_ALLOWED_HOSTS`.
- No database credentials in the image: credentials are created in Trifle and delivered through the control-plane job contract in later phases.
- Private CA support: set `TRIFLE_CONNECTOR_CA_FILE` when Trifle Cloud is served behind a private CA.
- Health-only mode: set `TRIFLE_CONNECTOR_CONTROL_PLANE_DISABLED=true` to validate deployment without a token.

## Quick Start

Create a private connector in Trifle first, then run the generated command. A minimal command looks like:

```bash
docker run -d --name trifle-connector \
  -e TRIFLE_CLOUD_URL="https://app.trifle.io" \
  -e TRIFLE_CONNECTOR_TOKEN="connector_registration_token" \
  -e TRIFLE_CONNECTOR_ID="prod-us-east-1" \
  -e TRIFLE_CONNECTOR_NAME="Production VPC" \
  -e TRIFLE_CONNECTOR_ALLOWED_HOSTS="postgres.internal:5432,redis.internal:6379,10.20.0.0/16" \
  trifle/connector:latest
```

Expose the health endpoint only when you need local observability:

```bash
docker run -d --name trifle-connector \
  -p 8080:8080 \
  -e TRIFLE_CONNECTOR_HEALTH_ADDR="0.0.0.0:8080" \
  -e TRIFLE_CONNECTOR_TOKEN="connector_registration_token" \
  -e TRIFLE_CONNECTOR_ALLOWED_HOSTS="postgres.internal:5432" \
  trifle/connector:latest
```

## Configuration

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `TRIFLE_CONNECTOR_TOKEN` | Yes | | Bearer token issued by Trifle Cloud. Not required when health-only mode is enabled. |
| `TRIFLE_CLOUD_URL` | No | `https://app.trifle.io` | Trifle Cloud base URL. |
| `TRIFLE_CONNECTOR_ID` | No | container hostname | Stable connector identifier shown in Trifle. |
| `TRIFLE_CONNECTOR_NAME` | No | | Human-readable name for the connector. |
| `TRIFLE_CONNECTOR_ALLOWED_HOSTS` | For network jobs | | Comma-separated host allowlist. Supports `host`, `host:port`, `*.domain`, CIDR ranges, and `*`. |
| `TRIFLE_CONNECTOR_CAPABILITIES` | No | `postgres,mysql,mongo,redis` | Capabilities reported to Trifle Cloud. |
| `TRIFLE_CONNECTOR_HEALTH_ADDR` | No | `127.0.0.1:8080` | Health server bind address. |
| `TRIFLE_CONNECTOR_POLL_INTERVAL` | No | `5s` | Job polling interval. Numeric values are seconds. |
| `TRIFLE_CONNECTOR_HEARTBEAT_INTERVAL` | No | `30s` | Heartbeat interval. Numeric values are seconds. |
| `TRIFLE_CONNECTOR_REQUEST_TIMEOUT` | No | `15s` | Control-plane HTTP timeout. |
| `TRIFLE_CONNECTOR_CA_FILE` | No | | Path to a PEM bundle appended to system roots. |
| `TRIFLE_CONNECTOR_INSECURE_SKIP_VERIFY` | No | `false` | Disables TLS verification. Development only. |
| `TRIFLE_CONNECTOR_CONTROL_PLANE_DISABLED` | No | `false` | Runs only the health server. Useful for deployment smoke tests. |

## Health Checks

The image includes a Docker health check:

```bash
docker inspect --format '{{json .State.Health}}' trifle-connector
```

The connector exposes:

- `GET /healthz`: process health.
- `GET /readyz`: JSON runtime status, including last heartbeat, last poll, and last error.

## Current Job Contract

The connector polls:

```http
GET /api/v1/connectors/jobs?connector_id=<connector_id>
```

The cloud response should be:

```json
{
  "data": {
    "jobs": [
      {
        "id": "job_123",
        "type": "tcp_check",
        "payload": { "host": "postgres.internal", "port": 5432, "timeout_seconds": 5 }
      }
    ]
  }
}
```

The connector completes jobs with:

```http
POST /api/v1/connectors/jobs/<job_id>/complete
```

Supported phase-2 jobs:

- `ping`: returns the connector ID and timestamp.
- `tcp_check` or `database_tcp_check`: checks TCP reachability for an allowed `host` and `port`, or an `address` in `host:port` form.

## Build

Build the local architecture:

```bash
./.devops/scripts/build-connector.sh
```

Build a specific release tag:

```bash
./.devops/scripts/build-connector.sh 0.15.0 amd64
```

Build and push a multi-platform image:

```bash
./.devops/scripts/build-connector.sh 0.15.0 multi trifle/connector
```

The Dockerfile lives at `.devops/docker/connector/Dockerfile` and uses `connector` as the build context.
