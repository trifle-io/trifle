# Trifle Agent

The Trifle Agent is a small Dockerized connector for databases that are not reachable from Trifle Cloud by IP allowlist or SSH tunnel. It runs inside the customer's network and opens outbound HTTPS connections to Trifle Cloud, so private databases can stay off the public internet.

This is the phase-2 container and runtime contract. The cloud-side control plane is expected to expose the `/api/v1/agents/*` endpoints described below.

## Security Model

- Outbound-only: the agent does not require inbound access from Trifle Cloud.
- Token-authenticated: every control-plane request uses `TRIFLE_AGENT_TOKEN` or shared `TRIFLE_TOKEN` as a bearer token.
- Least-reachability: network jobs are constrained by `TRIFLE_AGENT_ALLOWED_HOSTS`.
- No database credentials in the image: credentials are created in Trifle and delivered through the control-plane job contract in later phases.
- Private CA support: set `TRIFLE_AGENT_CA_FILE` when Trifle Cloud is served behind a private CA.
- Health-only mode: set `TRIFLE_AGENT_CONTROL_PLANE_DISABLED=true` to validate deployment without a token.

## Quick Start

```bash
docker run -d --name trifle-agent \
  -e TRIFLE_CLOUD_URL="https://app.trifle.io" \
  -e TRIFLE_AGENT_TOKEN="agent_registration_token" \
  -e TRIFLE_AGENT_ID="prod-us-east-1" \
  -e TRIFLE_AGENT_NAME="Production VPC" \
  -e TRIFLE_AGENT_ALLOWED_HOSTS="postgres.internal:5432,redis.internal:6379,10.20.0.0/16" \
  trifle/agent:latest
```

Expose the health endpoint only when you need local observability:

```bash
docker run -d --name trifle-agent \
  -p 8080:8080 \
  -e TRIFLE_AGENT_HEALTH_ADDR="0.0.0.0:8080" \
  -e TRIFLE_AGENT_TOKEN="agent_registration_token" \
  -e TRIFLE_AGENT_ALLOWED_HOSTS="postgres.internal:5432" \
  trifle/agent:latest
```

## Configuration

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `TRIFLE_AGENT_TOKEN` | Yes | | Bearer token issued by Trifle Cloud. Falls back to `TRIFLE_TOKEN`. Not required when health-only mode is enabled. |
| `TRIFLE_CLOUD_URL` | No | `https://app.trifle.io` | Trifle Cloud base URL. |
| `TRIFLE_AGENT_ID` | No | container hostname | Stable agent identifier shown in Trifle. |
| `TRIFLE_AGENT_NAME` | No | | Human-readable name for the agent. |
| `TRIFLE_AGENT_ALLOWED_HOSTS` | For network jobs | | Comma-separated host allowlist. Supports `host`, `host:port`, `*.domain`, CIDR ranges, and `*`. |
| `TRIFLE_AGENT_CAPABILITIES` | No | `postgres,mysql,mongo,redis` | Capabilities reported to Trifle Cloud. |
| `TRIFLE_AGENT_HEALTH_ADDR` | No | `127.0.0.1:8080` | Health server bind address. |
| `TRIFLE_AGENT_POLL_INTERVAL` | No | `5s` | Job polling interval. Numeric values are seconds. |
| `TRIFLE_AGENT_HEARTBEAT_INTERVAL` | No | `30s` | Heartbeat interval. Numeric values are seconds. |
| `TRIFLE_AGENT_REQUEST_TIMEOUT` | No | `15s` | Control-plane HTTP timeout. |
| `TRIFLE_AGENT_CA_FILE` | No | | Path to a PEM bundle appended to system roots. |
| `TRIFLE_AGENT_INSECURE_SKIP_VERIFY` | No | `false` | Disables TLS verification. Development only. |
| `TRIFLE_AGENT_CONTROL_PLANE_DISABLED` | No | `false` | Runs only the health server. Useful for deployment smoke tests. |

## Health Checks

The image includes a Docker health check:

```bash
docker inspect --format '{{json .State.Health}}' trifle-agent
```

The agent exposes:

- `GET /healthz`: process health.
- `GET /readyz`: JSON runtime status, including last heartbeat, last poll, and last error.

## Current Job Contract

The agent polls:

```http
GET /api/v1/agents/jobs?agent_id=<agent_id>
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

The agent completes jobs with:

```http
POST /api/v1/agents/jobs/<job_id>/complete
```

Supported phase-2 jobs:

- `ping`: returns the agent ID and timestamp.
- `tcp_check` or `database_tcp_check`: checks TCP reachability for an allowed `host` and `port`, or an `address` in `host:port` form.

## Build

Build the local architecture:

```bash
./.devops/scripts/build-agent.sh
```

Build a specific release tag:

```bash
./.devops/scripts/build-agent.sh 0.15.0 amd64
```

Build and push a multi-platform image:

```bash
./.devops/scripts/build-agent.sh 0.15.0 multi trifle/agent
```

The Dockerfile lives at `.devops/docker/agent/Dockerfile` and uses `agent` as the build context.
