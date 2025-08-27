# Production Deployment

This directory contains production deployment configurations for Trifle.

## Docker Compose (Local Production)

To run a production-ready instance locally using Docker Compose:

### Prerequisites

1. Docker and Docker Compose installed
2. Build the environment image first (if not available):
   ```bash
   cd .devops/docker/environment
   docker build -t trifle/environment:ruby_3.2.0-erlang_25.1.2-elixir_1.14.2_2 .
   ```

### Setup

1. Navigate to the production directory:
   ```bash
   cd .devops/docker/production
   ```

2. Copy the environment example file:
   ```bash
   cp .env.example .env
   ```

3. Edit `.env` and set your production values:
   ```bash
   # Generate a secret key base
   SECRET_KEY_BASE=$(openssl rand -base64 48)
   
   # Set secure passwords
   POSTGRES_PASSWORD=your_secure_postgres_password
   MONGO_PASSWORD=your_secure_mongo_password
   
   # Set your domain
   PHX_HOST=your-domain.com
   ```

4. Start the services:
   ```bash
   docker-compose up -d
   ```

5. Run database migrations:
   ```bash
   docker-compose exec app ./bin/trifle eval "Trifle.Release.migrate"
   ```

### Services

The docker-compose setup includes:

- **app**: Trifle application (port 4000)
- **postgres**: PostgreSQL database (port 5432) 
- **mongodb**: MongoDB for metrics storage (port 27017)
- **redis**: Redis for caching (port 6379)

### Volumes

Persistent data is stored in named Docker volumes:

- `postgres_data`: PostgreSQL data
- `mongodb_data`: MongoDB data  
- `redis_data`: Redis data
- `app_uploads`: Application uploaded files

### Health Checks

All services include health checks. Check status with:
```bash
docker-compose ps
```

### Logs

View logs for all services:
```bash
docker-compose logs -f
```

Or for a specific service:
```bash
docker-compose logs -f app
```

### Backup

To backup data:
```bash
# PostgreSQL
docker-compose exec postgres pg_dump -U trifle trifle_prod > backup.sql

# MongoDB
docker-compose exec mongodb mongodump --uri="mongodb://trifle:password@localhost:27017/trifle_metrics"
```

### SSL/TLS

For production with SSL, modify the docker-compose.yml to:

1. Add SSL certificate volumes
2. Configure the app service with SSL environment variables
3. Use a reverse proxy like nginx or traefik

## Kubernetes Deployment

See the Kubernetes Helm chart documentation in `.devops/kubernetes/`.