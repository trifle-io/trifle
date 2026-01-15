# Trifle CLI

The Trifle CLI talks to the Trifle API (`/api/v1`) to fetch or submit metrics and to provide an MCP server mode for agents.

## Install
- Download a release from GitHub (macOS/Linux).
- Or build locally: `cd cli && go build -o trifle .`

## Configuration
- `TRIFLE_URL`: Base URL for Trifle (e.g. `https://trifle.example.com`).
- `TRIFLE_TOKEN`: API token with read/write scopes.

Flags override env vars: `--url`, `--token`.

If no token is provided, the CLI prompts. MCP mode requires the token upfront.

## Examples

Fetch available metric keys:
```
trifle metrics keys --from 2024-01-01T00:00:00Z --to 2024-01-02T00:00:00Z
```

Fetch raw series:
```
trifle metrics get --key analytics.orders --from 2024-01-01T00:00:00Z --to 2024-01-02T00:00:00Z --granularity 1h
```

Aggregate series:
```
trifle metrics aggregate --key analytics.orders --value-path data.total --aggregator sum --from 2024-01-01T00:00:00Z --to 2024-01-02T00:00:00Z
```

Format timeline:
```
trifle metrics timeline --key analytics.orders --value-path data.total --from 2024-01-01T00:00:00Z --to 2024-01-02T00:00:00Z
```

Submit a metric:
```
trifle metrics push --key analytics.orders --values '{"total": 3, "region": "eu"}'
```

List transponders:
```
trifle transponders list
```

## MCP
Start the MCP server:
```
TRIFLE_URL=https://trifle.example.com TRIFLE_TOKEN=... trifle mcp
```

Resources:
- `trifle://source`
- `trifle://metrics?from=...&to=...&granularity=...`
- `trifle://metrics/{key}?from=...&to=...&granularity=...`
- `trifle://transponders`

Tools:
- `list_metrics`
- `fetch_series`
- `aggregate_series`
- `format_timeline`
- `format_category`
- `write_metric`
- `list_transponders`
