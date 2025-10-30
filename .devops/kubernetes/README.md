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
  host: "trifle.yourdomain.com"
  logLevel: "info"  # Accepts debug, info, warn, error

# Initial user creation
initialUser:
  enabled: true
  email: "admin@yourdomain.com"
  password: "secure-initial-password"  # Change after first login
  admin: true
  
# Resource limits
resources:
  limits:
    cpu: 2000m
    memory: 2Gi
  requests:
    cpu: 1000m
    memory: 1Gi

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
