# Local Database Setup

This docker-compose configuration provides only the database services needed for Trifle development, allowing you to run the Phoenix application locally while using Docker for database infrastructure.

## Services

- **PostgreSQL**: Port 5432 (main application database)
- **MongoDB**: Port 27017 (stats storage) 
- **Redis**: Port 6379 (caching/sessions)

## Usage

1. Start the databases:
   ```bash
   cd .devops/docker/local_db
   docker-compose up -d
   ```

2. Run your Phoenix app locally:
   ```bash
   # From project root
   mix deps.get
   mix ecto.setup
   mix phx.server
   ```

3. Stop the databases:
   ```bash
   docker-compose down
   ```

## Configuration

The databases are configured to match your `config/dev.exs`:

- **PostgreSQL**: 
  - Host: `localhost:5432`
  - User: `postgres`
  - Password: `password` 
  - Database: `trifle_dev`

- **MongoDB**:
  - Host: `localhost:27017`
  - No authentication

- **Redis**:
  - Host: `localhost:6379`
  - No authentication

## Data Persistence

Data is persisted in Docker volumes:
- `postgres_data`
- `mongo_data` 
- `redis_data`

To completely reset databases:
```bash
docker-compose down -v
```