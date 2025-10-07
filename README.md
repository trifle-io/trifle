# Trifle Analytics Platform

A Phoenix LiveView analytics platform with metrics tracking capabilities built on MongoDB and PostgreSQL.

## 🚀 Deployment

### Automated Docker Builds
Docker images are automatically built and pushed to Docker Hub via GitHub Actions:
- **Environment Image**: `trifle/environment` (Ruby, Erlang, Elixir)
- **Application Image**: `trifle/app` (Your application)
- **Multi-platform**: Both AMD64 and ARM64 architectures
- **Triggers**: Every push to `main` and version tags

### Kubernetes Deployment
Use the Helm chart for easy Kubernetes deployment:
```bash
helm install trifle .devops/kubernetes/helm/trifle
```

See [Kubernetes README](.devops/kubernetes/README.md) for detailed deployment instructions.

## Development Setup

### Prerequisites

- Elixir 1.18.4
- Phoenix Framework
- PostgreSQL (for application data)
- MongoDB (for metrics storage via trifle_stats package)

### Database Setup

You can run databases locally using Docker:

```bash
# Start database-only services
cd .devops/docker/local_db
docker-compose up -d
```

This exposes:
- PostgreSQL on port 5432
- MongoDB on port 27017

### Running the Application

```bash
# Install dependencies
mix deps.get

# Setup database
mix ecto.setup

# Start Phoenix server
mix phx.server
```

Visit [`http://localhost:4000`](http://localhost:4000) to access the application.

## API Testing and Data Population

The application provides a metrics API for programmatic data submission. You'll need to create a project token with write permissions first.

### Quick API Testing

Use the CURL test script for quick API validation:

```bash
./test_metrics.sh YOUR_PROJECT_TOKEN
```

This submits 4 sample metrics with different data structures to test the API endpoints.

### Bulk Data Population

For populating larger datasets, use either the Mix task or batch script:

#### Option 1: Mix Task (Small Datasets)

```bash
# Basic usage (50 metrics over 48 hours)
mix populate_metrics --token=YOUR_PROJECT_TOKEN

# Custom parameters
mix populate_metrics --token=YOUR_PROJECT_TOKEN --count=100 --hours=24
```

**Parameters:**
- `--token`: Your project API token (required)
- `--count`: Number of metrics to generate (default: 50)
- `--hours`: Time range in hours for historical spread (default: 48)

#### Option 2: Batch Script (Large Datasets - Recommended)

For larger datasets, use the batch script which processes data in small chunks to avoid server overload:

```bash
# Basic usage (100 metrics over 24 hours)
./populate_batch.sh YOUR_PROJECT_TOKEN

# Custom parameters
./populate_batch.sh YOUR_PROJECT_TOKEN TOTAL_COUNT HOURS

# Examples:
./populate_batch.sh YOUR_TOKEN 500 72    # 500 metrics over 3 days
./populate_batch.sh YOUR_TOKEN 1000 168  # 1000 metrics over 1 week
./populate_batch.sh YOUR_TOKEN 100 48    # 100 metrics over 2 days
```

**Parameters:**
1. `YOUR_TOKEN` (required) - Project API token with write permissions
2. `TOTAL_COUNT` (optional) - Total metrics to generate (default: 100)
3. `HOURS` (optional) - Time range in hours (default: 24)

**Why use the batch script?**
- Processes data in chunks of 15 to avoid overwhelming the server
- Includes automatic recovery and cooldown periods
- Better for large datasets (500+ metrics)
- Each batch runs as a separate process, preventing resource leaks

### Metric Types Generated

Both population methods generate realistic test data for these metric types:

- **page_views**: Total/unique views, page breakdown, traffic sources
- **user_signups**: Count, conversion rates, signup sources
- **api_calls**: Total calls, endpoint breakdown, HTTP status codes
- **errors**: Error counts by type and severity
- **performance**: Response times, memory/CPU usage
- **sales**: Revenue, orders, product categories

### API Authentication

The metrics API uses standard `Authorization: Bearer` headers:

```bash
curl -X POST "http://localhost:4000/api/metrics" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "key": "page_views",
    "at": "2024-01-15T10:30:00Z",
    "values": {
      "total": 1250,
      "unique": 890
    }
  }'
```

### Troubleshooting

**Server becomes unresponsive after ~25 requests:**
- Use the batch script instead of the Mix task
- Reduce batch sizes if needed
- Ensure adequate server resources

**Authentication errors (401):**
- Verify your token has write permissions
- Check token format (should start with `SFMyNTY.`)
- Ensure Phoenix server is running on localhost:4000

**File descriptor errors:**
- Restart the Phoenix server
- Use smaller batch sizes
- Check system ulimit settings

## Project Structure

- **Phoenix LiveView** for real-time analytics dashboard
- **MongoDB** for high-performance metrics storage
- **PostgreSQL** for application data (users, projects, tokens)
- **TailwindCSS** for styling
- **Alpine.js** for client-side interactions

## Design System

### UI Components

The application includes a comprehensive design system with reusable components for consistent styling:

#### **Form Components**
```elixir
# Unified form field with validation and error handling
<.form_field field={@form[:email]} type="email" label="Email" required />
<.form_field field={@form[:description]} type="textarea" label="Description" help_text="Optional" />
<.form_field field={@form[:status]} type="select" label="Status" options={@options} prompt="Choose..." />

# Standardized form buttons
<.form_actions>
  <.primary_button phx-disable-with="Saving...">Save</.primary_button>
  <.secondary_button navigate={~p"/back"}>Cancel</.secondary_button>
  <.danger_button data-confirm="Are you sure?">Delete</.danger_button>
</.form_actions>

# Form container with layout support
<.form_container for={@form} phx-submit="save" layout="simple">
  <:header title="Create Item" subtitle="Add a new item" />
  <.form_field field={@form[:name]} label="Name" required />
  <:actions>
    <.primary_button>Create</.primary_button>
    <.secondary_button navigate={~p"/back"}>Cancel</.secondary_button>
  </:actions>
</.form_container>
```

#### **Navigation Components**
```elixir
# Tab navigation
<.tab_navigation>
  <:tab navigate={~p"/explore"} active={true}>
    <:icon><svg>...</svg></:icon>
    <:label>Explore</:label>
  </:tab>
</.tab_navigation>

# Button groups
<.button_group label="Controls">
  <:button phx-click="action" title="Action">
    <.icon />
  </:button>
</.button_group>
```

#### **Data Display Components**
```elixir
# Data tables with headers and search
<.data_table>
  <:header>
    <.table_header title="Items" count={@count}>
      <:search>
        <input placeholder="Search..." />
      </:search>
    </.table_header>
  </:header>
  <:body>
    <!-- table content -->
  </:body>
</.data_table>

# Modals
<.app_modal id="my-modal" show={@show}>
  <:title>Modal Title</:title>
  <:body>Modal content</:body>
  <:actions>
    <.primary_button>Confirm</.primary_button>
  </:actions>
</.app_modal>
```

#### **Design System Benefits**
- **Consistent styling** across all UI components
- **Built-in dark mode support** for all components
- **Accessible design** with proper ARIA labels and keyboard navigation
- **Validation handling** with unified error display patterns
- **Flexible layouts** supporting simple, grid, and slide-over patterns

### Official Chart Color Palette

The analytics dashboard uses a carefully curated color palette managed by the `TrifleApp.DesignSystem.ChartColors` module:

```elixir
# Access the color palette in Elixir
alias TrifleApp.DesignSystem.ChartColors

ChartColors.palette()
# => ["#14b8a6", "#f59e0b", "#ef4444", "#8b5cf6", "#06b6d4", "#10b981", 
#     "#f97316", "#ec4899", "#3b82f6", "#84cc16", "#f43f5e", "#6366f1"]

ChartColors.color_for(0)     # => "#14b8a6" (Teal-600)
ChartColors.color_for(12)    # => "#14b8a6" (cycles back)
ChartColors.primary()        # => "#14b8a6" (primary color)
ChartColors.count()          # => 12
```

**The 12 Official Colors:**
1. `#14b8a6` - Teal-600 (primary)
2. `#f59e0b` - Amber-500
3. `#ef4444` - Red-500
4. `#8b5cf6` - Violet-500
5. `#06b6d4` - Cyan-500
6. `#10b981` - Emerald-500
7. `#f97316` - Orange-500
8. `#ec4899` - Pink-500
9. `#3b82f6` - Blue-500
10. `#84cc16` - Lime-500
11. `#f43f5e` - Rose-500
12. `#6366f1` - Indigo-500

**Color Palette Features:**
- **12 unique colors** providing excellent distinction between data series
- **Tailwind CSS based** ensuring consistency with the overall design system
- **Accessible contrast** meeting WCAG guidelines
- **Vibrant palette** excluding grays, whites, and blacks for maximum visibility
- **Automatic cycling** when more than 12 data series are present

**Usage Examples:**
```elixir
# Get colors for a list of keys
keys = ["api_calls", "page_views", "user_signups"]
ChartColors.colors_for(keys)
# => [{"api_calls", "#14b8a6"}, {"page_views", "#f59e0b"}, {"user_signups", "#ef4444"}]

# Get JSON-encoded palette for JavaScript
ChartColors.json_palette()
# => "[\"#14b8a6\",\"#f59e0b\",\"#ef4444\"...]"
```

The palette is used throughout the analytics dashboard for:
- Stacked bar charts showing multiple metrics  
- Individual key visualizations
- Legend indicators
- Data series differentiation
- JavaScript chart libraries (automatically injected via data attributes)

## Deployment

### Versioning & Docker images

- The application version is defined in the root `VERSION` file and consumed by `mix.exs`.
- GitHub Actions reads this version and tags the Docker image as both `latest` (for `main`) and `<VERSION>`.
- Helm charts default to using the chart `appVersion` when `image.tag` is left blank (see `.devops/kubernetes/helm/trifle/values.yaml`).
- When bumping the version, update `VERSION` and `Chart.yaml`'s `version`/`appVersion`, then commit the change before triggering CI.

### Monitoring & error reporting

- Honeybadger support remains available via `app.honeybadger.apiKey` in your values file.
- AppSignal can be enabled by setting `app.appsignal.enabled: true` and providing the relevant values (OTP app, name, env, and `pushApiKey`).
- When AppSignal is enabled, the Helm chart injects the following environment variables: `APPSIGNAL_OTP_APP`, `APPSIGNAL_APP_NAME`, `APPSIGNAL_APP_ENV`, and `APPSIGNAL_PUSH_API_KEY`.

### Email delivery

- Mail delivery is now fully configurable via Helm by setting `app.mailer.adapter` and the provider-specific keys under `app.mailer.*`.
- Supported adapters out of the box: `local` (default), `smtp`, `postmark`, `sendgrid`, `mailgun`, and `sendinblue`/`brevo`.
- Define the sender identity with `app.mailer.from.name` and `app.mailer.from.email`. Credentials (API keys, SMTP username/password) are written to the release secret automatically.
- Example—Brevo (Sendinblue):
  ```yaml
  app:
    mailer:
      adapter: "sendinblue"
      from:
        name: "Trifle"
        email: "no-reply@example.com"
      sendinblue:
        apiKey: "YOUR_BREVO_KEY"
  ```
- Example—SMTP:
  ```yaml
  app:
    mailer:
      adapter: "smtp"
      from:
        name: "Trifle"
        email: "no-reply@example.com"
      smtp:
        relay: "smtp.example.com"
        username: "smtp-user"
        password: "smtp-pass"
        port: 587
        auth: "if_available"
        tls: "if_available"
        ssl: false
  ```
  Optional keys such as `smtp.retries` or `mailgun.baseUrl` can be provided when needed.

### Docker Compose (Production)

For production deployment using Docker Compose:

```bash
cd .devops/docker/production
cp .env.example .env
# Edit .env with your production values
docker-compose up -d
```

### Kubernetes (Helm)

For Kubernetes deployment using Helm:

```bash
helm install trifle .devops/kubernetes/helm/trifle \
  --set app.secretKeyBase="$(openssl rand -base64 48)" \
  --set postgresql.auth.password="$(openssl rand -base64 32)" \
  --set initialUser.email="admin@example.com"
```

Self-hosted mode is enabled by default (`app.deploymentMode=self_hosted`). If you’re operating the multi-tenant SaaS instance, override with `--set app.deploymentMode=saas`.

See detailed deployment documentation in `.devops/` directory.

## Phoenix Framework

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

### Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
