# Monitors API (v1)

Monitors automate scheduled reports or alerting rules. This doc outlines the API payloads and alert settings.

## Authentication

All requests use a source token:

```
Authorization: Bearer <PROJECT_OR_DATABASE_TOKEN>
```

Read/write permissions are enforced only for metrics endpoints. For monitors,
any valid project or database token can read and write.

Monitors are scoped to the organization that owns the token.

## Endpoints

- `GET /api/v1/monitors` – list monitors
- `GET /api/v1/monitors/:id` – fetch a monitor
- `POST /api/v1/monitors` – create
- `PUT /api/v1/monitors/:id` – update
- `DELETE /api/v1/monitors/:id` – delete

If an `alerts` array is supplied on create/update, it replaces the monitor’s alerts. Omitting `alerts` leaves existing alerts unchanged.

## Monitor object

Required fields on create:
- `name` (string)
- `type` (`report` | `alert`)
- `status` (`active` | `paused`)
- `source_type` (`database` | `project`)
- `source_id` (string UUID)

Additional fields by type:

Report monitors:
- `dashboard_id` (string UUID)
- `report_settings` (map)
- `delivery_channels` (array)
- `delivery_media` (array)

Alert monitors:
- `alert_metric_key` (string)
- `alert_metric_path` (string)
- `alert_timeframe` (string, ex: `1h`, `24h`)
- `alert_granularity` (string, ex: `5m`, `1h`)
- `alert_notify_every` (integer, default: 1)
- `alerts` (array)

Optional fields (both):
- `description` (string)
- `locked` (boolean)
- `target` (map)
- `segment_values` (map)

### Report settings

```
report_settings: {
  "frequency": "daily" | "weekly" | "monthly" | "hourly",
  "timeframe": "7d",
  "granularity": "1d"
}
```

### Delivery channels

```
delivery_channels: [
  {
    "channel": "email" | "slack_webhook" | "discord_webhook" | "webhook" | "custom",
    "label": "Primary",
    "target": "ops@example.com",
    "config": { ... }
  }
]
```

### Delivery media

```
delivery_media: [
  { "medium": "pdf" | "png_light" | "png_dark" | "file_csv" | "file_json" }
]
```

## Alerts

Each alert defines an analysis strategy and settings. Supported strategies:

- `threshold` – compare against a single value
- `range` – alert when outside a min/max range
- `hampel` – robust outlier detection
- `cusum` – cumulative sum change detection

Alert payload:

```
{
  "analysis_strategy": "threshold",
  "settings": {
    "threshold_direction": "above",
    "threshold_value": 100
  }
}
```

### Strategy settings

`threshold`:
- `threshold_direction`: `above` | `below`
- `threshold_value`: number (required)

`range`:
- `range_min_value`: number (required)
- `range_max_value`: number (required, must be greater than min)

`hampel`:
- `hampel_window_size`: integer > 0 (required)
- `hampel_k`: number > 0 (required)
- `hampel_mad_floor`: number >= 0 (required)
- `treat_nil_as_zero`: boolean (optional)

`cusum`:
- `cusum_k`: number >= 0 (required)
- `cusum_h`: number > 0 (required)

## Example create request

```
POST /api/v1/monitors
Authorization: Bearer <PROJECT_WRITE_TOKEN>

{
  "name": "Latency Alerts",
  "type": "alert",
  "status": "active",
  "source_type": "database",
  "source_id": "db-uuid",
  "alert_metric_key": "service.latency",
  "alert_metric_path": "p95",
  "alert_timeframe": "1h",
  "alert_granularity": "5m",
  "alert_notify_every": 1,
  "alerts": [
    {
      "analysis_strategy": "threshold",
      "settings": {
        "threshold_direction": "above",
        "threshold_value": 350
      }
    }
  ]
}
```
