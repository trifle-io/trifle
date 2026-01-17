# Dashboards API (v1)

This document describes how to create dashboards and widget payloads via the API.
Use it as input for agents that need to assemble dashboard JSON.

## Authentication

All requests use a source token:

```
Authorization: Bearer <PROJECT_OR_DATABASE_TOKEN>
```

Permissions are enforced by the token only for metrics endpoints. For dashboards,
any valid project or database token can read and write.

Dashboards are scoped to the organization that owns the token. API responses only include dashboards that are visible to the organization (`visibility: true`).

## Endpoints

- `GET /api/v1/dashboards` – list visible dashboards
- `GET /api/v1/dashboards/:id` – fetch a visible dashboard
- `POST /api/v1/dashboards` – create
- `PUT /api/v1/dashboards/:id` – update (visible dashboards only)
- `DELETE /api/v1/dashboards/:id` – delete (visible dashboards only)

## Dashboard object

Required fields on create:
- `name` (string)
- `key` (string) – metric key used for data resolution
- `source_type` (string, `database` | `project`)
- `source_id` (string, UUID of the source)

Optional fields:
- `visibility` (boolean, default: `true` for API-created dashboards)
- `locked` (boolean, default: `false`)
- `payload` (map, default: `{}`)
- `segments` (array, default: `[]`)
- `default_timeframe` (string, ex: `"24h"`, `"7d"`)
- `default_granularity` (string, ex: `"1h"`, `"1d"`)
- `group_id` (string, optional dashboard group)
- `position` (integer)

You may also pass a source object instead of `source_type` / `source_id`:

```
source: { "type": "database", "id": "<uuid>" }
```

## Payload structure

The dashboard `payload` is a map. The grid of widgets lives at:

```
payload.grid = [ ...widgets ]
```

### Common widget fields

Every widget is a map with:
- `id` (string, unique within dashboard) – use a UUID
- `type` (string)
- `title` (string, optional)
- `x`, `y`, `w`, `h` (integers, optional) – grid position in a 12-column grid

Defaults if omitted: `w: 3`, `h: 2`, `x: 0`, `y: 0`.

### Widget types

Below are the supported `type` values and their fields.

#### KPI (`type: "kpi"`)

Shows a single value with optional visuals.

Fields:
- `path` (string) – metric path
- `function` (string: `mean` | `sum` | `min` | `max`, default: `mean`)
- `subtype` (string: `number` | `split` | `goal`, default: `number`)
- `size` (string: `s` | `m` | `l`, default: `m`)
- `timeseries` (boolean, default: `false`) – show sparkline (number/split)
- `diff` (boolean, default: `false`) – show % change (split only)
- `goal_target` (number or string) – goal target (goal only)
- `goal_progress` (boolean, default: `false`) – show progress bar (goal only)
- `goal_invert` (boolean, default: `false`) – lower is better (goal only)

Example:
```
{
  "id": "a1b2c3",
  "type": "kpi",
  "title": "Total Revenue",
  "path": "sales.total",
  "function": "sum",
  "subtype": "number",
  "size": "l",
  "timeseries": true,
  "x": 0, "y": 0, "w": 4, "h": 3
}
```

#### Timeseries (`type: "timeseries"`)

Shows lines/areas/bars over time.

Fields:
- `paths` (array of strings) or `path` (string)
- `chart_type` (string: `line` | `area` | `bar`, default: `line`)
- `stacked` (boolean, default: `false`)
- `normalized` (boolean, default: `false`)
- `legend` (boolean, default: `false`)
- `y_label` (string, optional)

Example:
```
{
  "id": "ts-1",
  "type": "timeseries",
  "title": "Orders Over Time",
  "paths": ["orders.count", "orders.refunds"],
  "chart_type": "area",
  "stacked": true,
  "legend": true,
  "y_label": "Orders",
  "x": 0, "y": 3, "w": 8, "h": 4
}
```

#### Category (`type: "category"`)

Aggregates by category and renders a bar/pie chart.

Fields:
- `paths` (array of strings) or `path` (string)
- `chart_type` (string: `bar` | `pie` | `donut`, default: `bar`)

Example:
```
{
  "id": "cat-1",
  "type": "category",
  "title": "Signups by Source",
  "paths": ["signups.sources.*"],
  "chart_type": "donut"
}
```

#### Table (`type: "table"`)

Renders tabular values for one or more paths.

Fields:
- `paths` (array of strings) or `path` (string)

Example:
```
{
  "id": "tbl-1",
  "type": "table",
  "title": "Payment Methods",
  "paths": ["payments.methods.*"],
  "x": 0, "y": 7, "w": 12, "h": 5
}
```

#### Text (`type: "text"`)

Static or HTML content.

Fields:
- `subtype` (string: `header` | `html`, default: `header`)
- `title` (string) – used as headline for header subtype
- `subtitle` (string, optional; header subtype)
- `alignment` (string: `left` | `center` | `right`, default: `center`)
- `title_size` (string: `large` | `medium` | `small`, default: `large`)
- `color` (string: `default` | `slate` | `teal` | `amber` | `emerald` | `rose`)
- `payload` (string, HTML; html subtype only)

Example (header):
```
{
  "id": "text-1",
  "type": "text",
  "title": "Q1 Goals",
  "subtitle": "Revenue, activation, and retention targets.",
  "subtype": "header",
  "alignment": "left",
  "title_size": "large",
  "color": "slate",
  "x": 8, "y": 0, "w": 4, "h": 2
}
```

#### List (`type: "list"`)

Ranked list of category values.

Fields:
- `path` (string) – category map path
- `limit` (integer, optional)
- `sort` (string: `desc` | `asc` | `alpha` | `alpha_desc`, default: `desc`)
- `label_strategy` (string: `short` | `full_path`, default: `short`)
- `empty_message` (string, optional)

Example:
```
{
  "id": "list-1",
  "type": "list",
  "title": "Top Countries",
  "path": "geo.countries.*",
  "limit": 8,
  "sort": "desc",
  "label_strategy": "short"
}
```

#### Distribution (`type: "distribution"`)

Bucketed distribution charts (2D bar or 3D scatter).

Fields:
- `paths` (array of strings)
- `mode` (string: `2d` | `3d`, default: `2d`)
- `chart_type` (string, default: `bar`)
- `legend` (boolean, default: `true`)
- `designators` (map) – bucket definitions

Designators can be provided as:
```
designators: {
  "horizontal": { ... },
  "vertical": { ... }
}
```

Each designator supports:
- `type`: `custom` | `linear` | `geometric`
- `buckets`: array of numbers (for `custom`)
- `min`, `max`, `step`: numbers (for `linear`)
- `min`, `max`: numbers (for `geometric`)

Example:
```
{
  "id": "dist-1",
  "type": "distribution",
  "title": "Latency Distribution",
  "paths": ["latency.ms.*"],
  "mode": "2d",
  "legend": true,
  "designators": {
    "horizontal": { "type": "linear", "min": 0, "max": 1000, "step": 50 }
  }
}
```

## Segments

Segments allow dynamic dashboard keys and filters. Store an array in `segments`.

Segment fields:
- `id` (string, optional; will be generated if omitted)
- `name` (string, required; used in key substitution)
- `label` (string, optional; defaults to `name`)
- `type` (`select` or `text`, default: `select`)
- `placeholder` (string, optional)
- `default_value` (string, optional)
- `groups` (array; select type only)

Select groups example:
```
[
  {
    "id": "segment-1",
    "name": "region",
    "label": "Region",
    "type": "select",
    "groups": [
      {
        "label": "Primary",
        "items": [
          { "value": "us", "label": "United States" },
          { "value": "eu", "label": "Europe" }
        ]
      }
    ]
  }
]
```

## Example create request

```
POST /api/v1/dashboards
Authorization: Bearer <PROJECT_WRITE_TOKEN>

{
  "name": "Product Analytics",
  "key": "product.events",
  "source_type": "database",
  "source_id": "db-uuid",
  "default_timeframe": "7d",
  "default_granularity": "1h",
  "payload": {
    "grid": [
      {
        "id": "kpi-1",
        "type": "kpi",
        "title": "Active Users",
        "path": "users.active",
        "function": "sum",
        "size": "l",
        "timeseries": true,
        "x": 0, "y": 0, "w": 4, "h": 3
      }
    ]
  }
}
```
