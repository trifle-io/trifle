# GitHub Actions Setup

This repository uses GitHub Actions to run tests and build/push Docker images to Docker Hub.

## Required Secrets

Configure these secrets in your GitHub repository settings (`Settings > Secrets and variables > Actions`):

### Docker Hub Authentication
- `DOCKERHUB_USERNAME`: Your Docker Hub username
- `DOCKERHUB_TOKEN`: Your Docker Hub access token (not password)

### How to Create Docker Hub Access Token
1. Go to https://hub.docker.com/settings/security
2. Click "New Access Token"
3. Name it `github-actions-trifle`
4. Copy the token and add it as `DOCKERHUB_TOKEN` secret

## What the Workflows Do

### CI Tests (`ci.yml`)
**Triggers**:
- **Push to any branch**: Runs `mix test` in Docker

**Process**:
1. **Builds the app image** from `docker-compose.yml`
2. **Starts Postgres/Mongo/Redis**
3. **Runs `mix test`** inside the app container
4. **Tears down** services after the run

### Application Build (`build-and-push-images.yml`)
**Triggers**:
- **Push to main**: Builds for validation (no push)
- **Push tags (v*)**: Builds and pushes `trifle/app` with the git tag
- **Pull requests**: Builds for testing only (no push)

**Process**:
1. **Uses existing environment image** from Docker Hub
2. **Builds assets** with Node.js/Elixir on GitHub Actions
3. **Builds application image** with pre-compiled assets
4. **Multi-platform**: AMD64 and ARM64
5. **Security scanning**: Trivy vulnerability checks (shows in build logs)

### Environment Build (`build-environment-image.yml`)
**Triggers**:
- **Changes to** `.devops/docker/environment/` files
- **Manual trigger**: For version upgrades

**Process**:
1. **Builds base environment** with Ruby, Erlang, Elixir
2. **Only when needed**: Not on every deployment
3. **Manual control**: Can specify versions via workflow dispatch

### Image Tags Generated
- `trifle/environment:ruby_3.2.0-erlang_28.0.2-elixir_1.18.4`
- `trifle/environment:latest`
- `trifle/app:1.2.3` (when you tag releases like `v1.2.3`)

## Usage

### Automatic Deployment
Only git tag pushes (matching `v*`) build and push images to Docker Hub.

### Manual Trigger
You can manually trigger the workflow from the GitHub Actions tab.

### Version Releases
```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```
This creates `trifle/app:1.0.0` images.

### Using in Kubernetes
Your Helm charts will automatically pull the latest multi-platform images:
```yaml
image:
  repository: trifle/app
  tag: 1.0.0  # or a newer release tag
```

## Security Scanning

### Free/Personal Repositories
- **Trivy security scan** runs automatically
- **Results shown** in build logs (Actions tab)
- **Build fails** if critical vulnerabilities found
- **GitHub Security tab** not available (requires GitHub Advanced Security)

### Organization Repositories with GitHub Advanced Security
- **Full SARIF integration** with GitHub Security tab
- **Vulnerability tracking** and remediation guidance
- **Automated security alerts**

## Monitoring

- Check the **Actions** tab for build status and security scan results
- Check **Security** tab for vulnerability reports (org repos only)
- Docker Hub shows download stats and image layers
