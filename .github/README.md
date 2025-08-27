# GitHub Actions Setup

This repository uses GitHub Actions to automatically build and push Docker images to Docker Hub.

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

## What the Workflow Does

### Triggers
- **Push to main**: Builds and pushes images tagged as `latest`
- **Push tags (v*)**: Builds and pushes images with version tags
- **Pull requests**: Builds images but doesn't push (for testing)

### Build Process
1. **Environment Image**: Builds `trifle/environment` with Elixir, Erlang, Ruby
2. **Application Image**: Builds `trifle/app` with your application
3. **Multi-platform**: Both AMD64 and ARM64 architectures
4. **Pre-built Assets**: Assets are built on GitHub Actions (avoiding segfaults)
5. **Security Scan**: Trivy vulnerability scanning
6. **Cache**: Uses GitHub Actions cache for faster builds

### Image Tags Generated
- `trifle/environment:ruby_3.2.0-erlang_28.0.2-elixir_1.18.4`
- `trifle/environment:latest`
- `trifle/app:latest`
- `trifle/app:v1.2.3` (when you tag releases)

## Usage

### Automatic Deployment
Every push to `main` automatically builds and pushes images to Docker Hub.

### Manual Trigger
You can manually trigger the workflow from the GitHub Actions tab.

### Version Releases
```bash
git tag v1.0.0
git push origin v1.0.0
```
This creates `trifle/app:v1.0.0` and `trifle/app:1.0` images.

### Using in Kubernetes
Your Helm charts will automatically pull the latest multi-platform images:
```yaml
image:
  repository: trifle/app
  tag: latest  # or specific version like "v1.0.0"
```

## Monitoring

- Check the **Actions** tab for build status
- Check **Security** tab for vulnerability reports
- Docker Hub shows download stats and image layers