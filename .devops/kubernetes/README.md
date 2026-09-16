# Kubernetes Deployment

This directory contains Kubernetes deployment configurations for Trifle using Helm.

## Prerequisites

- Kubernetes cluster (1.19+)
- Helm 3.8+
- kubectl configured for your cluster
- cert-manager (for SSL certificates)
- NGINX Ingress Controller (for ingress)

## Quick Start

1. Install prerequisites (if not already installed):
   ```bash
   # Install cert-manager
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
   
   # Install NGINX Ingress Controller (example for cloud providers)
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
   ```

2. Install Trifle with default values (uses the bundled PostgreSQL StatefulSet):
   ```bash
   helm install trifle ./helm/trifle \
     --set app.secretKeyBase="$(openssl rand -base64 48)" \
     --set app.dbEncryptionKey="$(openssl rand -base64 32)" \
     --set postgresql.auth.password="$(openssl rand -base64 32)" \
     --set initialUser.email="admin@example.com"
   ```

3. Check the installation:
   ```bash
   kubectl get pods -l app.kubernetes.io/name=trifle
   ```

## Configuration

### Basic Configuration

Create a `values-prod.yaml` file:

```yaml
# Application configuration
app:
  secretKeyBase: "your-64-character-secret-key"
  dbEncryptionKey: "your-32-byte-base64-key"
  host: "trifle.yourdomain.com"
  logLevel: "info"  # Accepts debug, info, warn, error
  sqliteUpload:
    maxBytes: 104857600
    rootPath: "/home/app/uploads/sqlite"
  sqliteStorage:
    backend: "local" # local | s3
    cacheRoot: "/home/app/cache/sqlite"
    objectStore:
      endpoint: ""
      bucket: ""
      region: "us-east-1"
      accessKeyId: ""
      secretAccessKey: ""
      forcePathStyle: true
      prefix: "sqlite-files"
  observability:
    enabled: true # Set false to disable the app's own Oban traces and Stats metrics.
    indexBackend: "postgres" # postgres | mongo; Mongo reuses app.mongodbUrl.
    granularities: ["1m", "1h", "1d", "1mo"]
    defaultTimeframe: "6h"
    defaultGranularity: "1m"
    timeZone: "UTC"
  traces:
    storageBackend: "file"
    storagePath: "/home/app/uploads/traces"
    retentionDays: 7
    gzip: true

# Initial user creation
initialUser:
  enabled: true
  email: "admin@yourdomain.com"
  password: "secure-initial-password"  # Change after first login
  admin: true
  
# Resource limits
resources:
  limits:
    cpu: "3"
    memory: 3Gi
  requests:
    cpu: 2000m
    memory: 2Gi

# Enable ingress with SSL
ingress:
  enabled: true
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    cert-manager.io/issuer: "{{ include \"trifle.fullname\" . }}-letsencrypt"
  hosts:
    - host: trifle.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: trifle-tls
      hosts:
        - trifle.yourdomain.com

# Certificate Manager (automatic SSL certificates)
certManager:
  enabled: true
  kind: "Issuer"  # Use "ClusterIssuer" if you prefer cluster-wide
  email: "admin@yourdomain.com"  # REQUIRED: Your email for Let's Encrypt

# Database password
postgresql:
  auth:
    password: "secure-postgres-password"
```

Install with your configuration:
```bash
helm install trifle ./helm/trifle -f values-prod.yaml
```

### External Database

To use an external PostgreSQL database, disable the internal one and configure external connection:

```yaml
# Disable internal database
postgresql:
  enabled: false

# Configure external database  
externalPostgresql:
  host: "postgres.yourdomain.com"
  username: "trifle"
  password: "secure-password"
  database: "trifle_prod"
```

### Projects Feature & MongoDB

The Projects UI and its ingest API are disabled by default when deploying with this chart.
Enable them by toggling the feature flag and, optionally, persistent storage for the bundled MongoDB sidecar:

```yaml
features:
  projects:
    enabled: true

mongo:
  persistence:
    enabled: true
    storageClass: "fast-ssd"
    size: 20Gi
```

When enabled, the Helm chart injects the official `mongo` container into the Trifle pod and exposes it at `localhost:27017/trifle`.
Leave MongoDB persistence disabled for ephemeral clusters or turn it on to provision a dedicated PVC named `<release>-mongo`.
Authentication defaults to disabled to match the application defaults; supply custom credentials and connection logic if you require secured MongoDB.

To use an external MongoDB cluster (no sidecar), disable the sidecar and set `app.mongodbUrl`:

```yaml
features:
  projects:
    enabled: true

mongo:
  sidecar:
    enabled: false

app:
  mongodbUrl: "mongodb://user:password@mongo-0.mongo.svc.cluster.local:27017,mongo-1.mongo.svc.cluster.local:27017,mongo-2.mongo.svc.cluster.local:27017/trifle_production?replicaSet=rs0&authSource=admin"
```

### Persistence

Configure persistent storage:

```yaml
# Application file storage
persistence:
  enabled: true
  storageClass: "fast-ssd"
  size: 20Gi

# Database storage
postgresql:
  primary:
    persistence:
      storageClass: "fast-ssd"
      size: 100Gi
```

SQLite uploads use `app.sqliteUpload.rootPath`.  
When `persistence.enabled: true`, keep this path under the mounted uploads directory (default `/home/app/uploads/sqlite`).

SQLite object storage is configured with `app.sqliteStorage`:
- `backend: local` keeps files on mounted storage.
- `backend: s3` stores uploads in S3-compatible object storage and reads via local cache (`cacheRoot`).
- `objectStore.accessKeyId` and `objectStore.secretAccessKey` are rendered into the app secret and injected as env vars.

Internal observability is enabled by default. Set `app.observability.enabled: false`
to disable the app's own Oban traces, their Stats metrics, and provisioning of new
internal database sources. This renders `TRIFLE_OBSERVABILITY_ENABLED` in the app,
migration job, and initial-user job. An explicit value in
`app.env.TRIFLE_OBSERVABILITY_ENABLED` takes precedence. Apply with your normal Helm
upgrade; this is a startup setting, not a live toggle. For non-Helm Kubernetes
deployments, set the same environment variable on the app and release jobs.

Disabling does not delete existing traces, metrics, or source records, and does not
affect user-configured sources or their retention cleanup. Existing S3 lifecycle
rules still apply. Ordinary application logging and third-party integrations are
configured separately.

When enabled, Trifle's internal background-job traces store searchable metadata and
Stats metrics in the database selected by `app.observability.indexBackend`. The default
is PostgreSQL. For MongoDB, use the dedicated `app.observability.mongodbUrlSecretRef`
or `app.observability.mongodbUrl`; the general `app.mongodbUrl` is only a fallback.

Internal Stats are tracked at `1m`, `1h`, `1d`, and `1mo` by default. Configure the
stored buckets with `app.observability.granularities` (or the comma-separated
`TRIFLE_OBSERVABILITY_GRANULARITIES`). The generated source opens at `6h` / `1m` by
default; `defaultTimeframe` and `defaultGranularity` configure those initial selections.
Internal Stats and their generated source use UTC by default. Configure both with
`app.observability.timeZone` or `TRIFLE_OBSERVABILITY_TIME_ZONE`.

Trace payload storage has independent S3-compatible settings and can reference a
dedicated Kubernetes Secret:

```yaml
app:
  observability:
    enabled: true
    indexBackend: mongo
    mongodbUrlSecretRef:
      name: trifle-observability
      key: mongodb-url
    granularities: ["1m", "1h", "1d", "1mo"]
    defaultTimeframe: "6h"
    defaultGranularity: "1m"
    timeZone: "UTC"
  traces:
    storageBackend: s3
    s3:
      endpoint: https://objects.example.com
      buckets: [trifle-internal-traces]
      region: us-east-1
      prefix: traces
      credentialsSecretRef:
        name: trifle-observability
        accessKeyIdKey: s3-access-key-id
        secretAccessKeyKey: s3-secret-access-key
    manageS3Lifecycle: false
    retentionDays: 7
```

Create the referenced Secret in the same namespace before the Helm upgrade. Set
`manageS3Lifecycle: false` when the bucket is shared. Add an object-store lifecycle
rule for `<retentionDays>/<s3.prefix>/` if trace payloads should expire automatically.
`app.traces.retentionDays` defaults to `7` and can be overridden in deployment values;
the default object prefix is `7/traces/`. Update the lifecycle rule when changing it.

Set `app.traces.storagePath` to retain the full trace narrative on a filesystem; leave it
blank for metadata-only traces. Keep the path under `persistence.mountPath` when using the
chart-managed PVC. With multiple application replicas, the payload path must be backed by
ReadWriteMany storage so every replica can read traces written by the others; otherwise use
a single replica or leave filesystem payload storage disabled.

The chart's observability regression checks only render templates; they do not
access a cluster. With Helm available inside the app container, run from the app root:

```sh
docker compose exec -T app elixir .devops/kubernetes/helm/test_observability.exs
```

Set `HELM_BIN` in the container if Helm is not on `PATH`.

### Autoscaling

Enable horizontal pod autoscaling:

```yaml
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

## Operations

### Initial User Management

The Helm chart can create an initial admin user during installation:

```yaml
# In your values file
initialUser:
  enabled: true
  email: "admin@yourdomain.com"
  password: "secure-password"
  admin: true
```

**Security Notes:**
- The initial user is automatically confirmed (no email verification needed)
- Change the password immediately after first login
- You can disable user creation by setting `initialUser.enabled: false`
- If a user with the specified email already exists, creation is skipped

### Upgrade

```bash
helm upgrade trifle ./helm/trifle -f values-prod.yaml
```

### Database Migrations

Run migrations manually:
```bash
kubectl exec -it deployment/trifle -- ./bin/trifle eval "Trifle.Release.migrate"
```

### Backup

PostgreSQL backup:
```bash
kubectl exec -it trifle-postgresql-0 -- pg_dump -U trifle trifle_prod > backup.sql
```

### Monitoring

The chart exposes application Prometheus metrics at `/metrics`. Deploy a PostgreSQL
exporter (for example, prometheus-postgres-exporter) if you need database-level metrics.

### SSL Certificate Management

The Helm chart includes automatic SSL certificate provisioning via cert-manager:

**Built-in Certificate Issuer:**
- The chart creates its own Certificate Issuer (namespace-scoped by default)
- Automatically provisions Let's Encrypt certificates
- Handles certificate renewal

**Configuration Options:**
```yaml
certManager:
  enabled: true
  kind: "Issuer"        # or "ClusterIssuer" for cluster-wide
  email: "your-email@domain.com"  # Required for Let's Encrypt
```

**Certificate Troubleshooting:**
```bash
# Check certificate status
kubectl get certificates
kubectl describe certificate trifle-tls

# Check certificate issuer
kubectl get issuer
kubectl describe issuer trifle-letsencrypt

# Check certificate challenges
kubectl get challenges
```

### Troubleshooting

Check pod logs:
```bash
kubectl logs -l app.kubernetes.io/name=trifle -f
```

Check services:
```bash
kubectl get svc -l app.kubernetes.io/name=trifle
```

Check ingress:
```bash
kubectl get ingress
```

Exec into application pod:
```bash
kubectl exec -it deployment/trifle -- /bin/bash
```

## Security

### Secrets Management

For production, use external secret management:

1. **External Secrets Operator**: 
   ```yaml
   app:
     secretKeyBase: ""  # Will be populated by external secret
     dbEncryptionKey: ""  # Will be populated by external secret
   ```

2. **Sealed Secrets**:
   ```bash
   echo -n "your-secret" | kubectl create secret generic trifle-secrets --dry-run=client --from-file=secret-key-base=/dev/stdin -o yaml | kubeseal -o yaml > sealed-secret.yaml
   ```

### RBAC

The chart creates a service account with minimal permissions. For additional security, customize the RBAC configuration.

### Network Policies

Implement network policies to restrict pod-to-pod communication:

```yaml
# Network policy example (not included in chart)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: trifle-netpol
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: trifle
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: nginx-ingress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: postgresql
```
