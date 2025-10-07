# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Setup and Dependencies
```bash
# Install dependencies and setup databases
mix setup

# Individual setup steps
mix deps.get
mix ecto.setup
mix assets.setup
mix assets.build
```

### Running the Application
```bash
# Start Phoenix server (runs on port 4000)
mix phx.server

# Start with IEx console
iex -S mix phx.server
```

### Database Operations
```bash
# Reset database completely
mix ecto.reset

# Create and run migrations
mix ecto.create
mix ecto.migrate

# Run seeds
mix run priv/repo/seeds.exs
```

### Asset Management
```bash
# Build assets for development
mix assets.build

# Build and minify for production
mix assets.deploy

# Install asset dependencies
mix tailwind.install
mix esbuild.install
```

### Testing and Data Population
```bash
# Run tests
mix test

# Run specific test file
mix test test/path/to/test_file.exs

# Populate test metrics data (requires project token)
mix populate_metrics --token=your_token_here --count=100 --hours=24

# Quick API test using script
./test_metrics.sh your_token_here
```

## Architecture Overview

### Core Components

**Multi-Database Architecture:**
- **PostgreSQL**: Application data (users, projects, tokens, authentication)
- **MongoDB**: High-performance metrics storage via `trifle_stats` package
- Each project gets isolated MongoDB collection: `proj_{project_id}`

**Phoenix LiveView Structure:**
- `TrifleApi.MetricsController` - REST API for metrics ingestion
- `TrifleApp.DesignSystem.ChartColors` - 12-color palette system for consistent visualization

### Metrics Architecture

**Data Flow:**
1. Metrics submitted via API → MongoDB (through trifle_stats)
2. LiveView queries aggregated data → Real-time dashboard updates
3. Stats configuration per project in `Trifle.Organizations.Project.stats_config/1`

**Key Concepts:**
- **Keys**: Metric identifiers (e.g., "page_views", "api_calls")
- **Values**: Nested data structures with arbitrary depth
- **Aggregation**: Automatic rollups by minute/hour/day/week/month/year
- **Time Zones**: Per-project timezone handling

### Authentication & Authorization
- **Project Tokens**: Bearer token authentication for API access
- **Read/Write Permissions**: Tokens can be scoped for different operations
- **Multi-tenant**: Projects are isolated with user-based access control

### Data Visualization
- **Apache Echarts Integration**: Time-series and stacked charts
- **Smart Timeframes**: Natural language inputs like "5m", "1d", "3w"
- **Color System**: Consistent 12-color palette with hierarchical path coloring
- **Interactive Tables**: Sticky headers, hover effects, nested path visualization

## Database Configuration

### MongoDB Connection
Default development connection managed in `Project.stats_config/1`:
```elixir
# MongoDB connection pool (reused across requests)
Mongo.start_link(url: "mongodb://localhost:27017/trifle", name: :trifle_mongo)
```

### Running Databases with Docker
```bash
cd .devops/docker/local_db
docker-compose up -d
```
This exposes PostgreSQL on port 5432 and MongoDB on port 27017.

## API Usage

### Metrics Submission
```bash
curl -X POST "http://localhost:4000/api/metrics" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "key": "page_views",
    "at": "2024-01-15T10:30:00Z",
    "values": {
      "total": 1250,
      "pages": {
        "home": 650,
        "dashboard": 400
      }
    }
  }'
```

### Data Structures
Values support arbitrary nesting:
- Simple counts: `{"count": 42}`
- Nested breakdowns: `{"pages": {"home": 100, "dashboard": 50}}`
- Multi-level hierarchies: `{"severity": {"high": {"database": 5}}}`

## Design System Components

**IMPORTANT**: Always use the design system components instead of creating custom UI. All components are imported in `TrifleApp` and available everywhere.

### Form Components
```elixir
# Use these standardized form components for ALL forms:

# 1. Form fields (replaces manual input/label/error handling)
<.form_field field={@form[:name]} label="Name" required />
<.form_field field={@form[:email]} type="email" label="Email" help_text="We'll never share your email" />
<.form_field field={@form[:driver]} type="select" label="Driver" options={@drivers} prompt="Choose driver..." />
<.form_field field={@form[:description]} type="textarea" label="Description" rows={6} />
<.form_field field={@form[:enabled]} type="checkbox" label="Enabled" />

# 2. Form buttons (consistent hierarchy)
<.form_actions align="right">
  <.primary_button phx-disable-with="Saving...">Save</.primary_button>
  <.secondary_button navigate={~p"/back"}>Cancel</.secondary_button>
  <.danger_button phx-click="delete" data-confirm="Are you sure?">Delete</.danger_button>
  <.ghost_button patch={~p"/edit"}>Edit</.ghost_button>
</.form_actions>

# 3. Form containers (replaces simple_form)
<.form_container for={@form} phx-submit="save" layout="simple">
  <:header title="Create Database" subtitle="Add a new database connection" />
  <.form_field field={@form[:name]} label="Name" required />
  <.form_field field={@form[:driver]} type="select" label="Driver" options={@drivers} />
  <:actions>
    <.primary_button>Create Database</.primary_button>
    <.secondary_button navigate={~p"/databases"}>Cancel</.secondary_button>
  </:actions>
</.form_container>

# Layout options: "simple" (default), "grid" (admin-style), "slide_over" (modal forms)
```

### UI Components
```elixir
# 1. Button groups (for controls like granularity, navigation)
<.button_group label="Granularity">
  <:button phx-click="set_granularity" phx-value-granularity="minute" selected={@granularity == "minute"}>
    1m
  </:button>
  <:button phx-click="set_granularity" phx-value-granularity="hour" selected={@granularity == "hour"}>
    1h
  </:button>
</.button_group>

# 2. Data tables (for list views)
<.data_table>
  <:header>
    <.table_header title="Items" count={@count}>
      <:search>
        <input phx-keyup="search" placeholder="Search..." />
      </:search>
    </.table_header>
  </:header>
  <:body>
    <ul class="divide-y">
      <!-- list items -->
    </ul>
  </:body>
</.data_table>

# 3. Modals (use app_modal, NOT the core modal)
<.app_modal id="error-modal" show={@show_errors} on_cancel="hide_errors">
  <:title>Transponder Errors</:title>
  <:body>
    Error details here...
  </:body>
  <:actions>
    <.secondary_button phx-click="hide_errors">Close</.secondary_button>
  </:actions>
</.app_modal>

# 4. Tab navigation (for page tabs)
<.tab_navigation>
  <:tab navigate={~p"/explore"} active={@current_tab == "explore"}>
    <:icon><svg>...</svg></:icon>
    <:label>Explore</:label>
  </:tab>
  <:tab navigate={~p"/transponders"} active={@current_tab == "transponders"}>
    <:icon><svg>...</svg></:icon>
    <:label>Transponders</:label>
  </:tab>
</.tab_navigation>
```

### Component Guidelines
- **ALWAYS use design system components** instead of creating custom UI
- **Form validation**: Use `form_field` component - it handles errors automatically
- **Button hierarchy**: Primary for main actions, secondary for cancel, danger for delete
- **Modal consistency**: Use `app_modal` with proper slot structure
- **Color scheme**: Components use teal primary, gray neutral, red danger

## Key Files & Modules

### Core LiveView Logic
- `lib/trifle_web/live/project_live.ex` - Main dashboard with 1,096 lines handling:
  - Smart timeframe parsing and URL parameter handling
  - Chart data serialization for Charts
  - Interactive filtering and drill-down
  - Hierarchical data path formatting

### Data Processing
- `lib/trifle/organizations/project.ex` - Project model and stats configuration
- `lib/trifle/stats/` - Statistics aggregation (depends on trifle_stats package)
- `lib/mix/tasks/populate_metrics.ex` - Test data generation with realistic nested structures

### Frontend Integration
- JavaScript hooks in `assets/js/app.js` for Charts integration
- `data-*` attributes pass configuration from Elixir to JavaScript
- Color palette automatically injected via `ChartColors.json_palette()`

## Development Notes

### Performance Considerations
- MongoDB collections are per-project for isolation
- Use batch scripts for large dataset testing (avoid mix task for >100 metrics)
- Connection pooling prevents resource exhaustion during bulk operations

### Time Zone Handling
- Projects have configurable time zones stored in `project.time_zone`
- All datetime inputs are timezone-naive (HTML datetime-local)
- Server converts to project timezone for storage and display

### Chart Color System
The design system enforces consistent coloring across all visualizations:
- 12 predefined colors cycle automatically
- Hierarchical paths get colors based on nesting level
- Keys maintain consistent colors between list view and charts
