#!/bin/bash

# 🚀 Build production Docker image for Trifle with dynamic versions
# Usage: ./build-production.sh [app_tag] [erlang_version] [elixir_version] [ruby_version] [platform] [skip_assets]
# 
# Examples:
#   ./build-production.sh                           # All defaults (current platform)
#   ./build-production.sh v1.0.0                    # Custom app tag
#   ./build-production.sh latest 27.3 1.17.3 3.1.4 # Custom versions
#   ./build-production.sh latest 28.0.2 1.18.4 3.2.0 multi # Multi-platform build
#   ./build-production.sh latest 28.0.2 1.18.4 3.2.0 amd64 true # Skip assets (build them locally first)

set -e

# Parse arguments with defaults
APP_TAG=${1:-latest}
ERLANG_VERSION=${2:-28.0.2}
ELIXIR_VERSION=${3:-1.18.4}
RUBY_VERSION=${4:-3.2.0}
PLATFORM=${5:-current}
SKIP_ASSETS=${6:-false}

APP_IMAGE_NAME="trifle/app"
ENV_IMAGE_NAME="trifle/environment"

# Generate dynamic environment tag from versions
generate_env_tag() {
    local ruby_v="$1"
    local erlang_v="$2" 
    local elixir_v="$3"
    echo "ruby_${ruby_v}-erlang_${erlang_v}-elixir_${elixir_v}"
}

ENV_TAG=$(generate_env_tag "$RUBY_VERSION" "$ERLANG_VERSION" "$ELIXIR_VERSION")
ENV_IMAGE="$ENV_IMAGE_NAME:$ENV_TAG"

echo "========================================"
echo "🚀 Building Production Image"
echo "========================================"
echo "App Image: $APP_IMAGE_NAME:$APP_TAG"
echo "Environment Image: $ENV_IMAGE"
echo "Platform: $PLATFORM"
echo "Ruby Version: $RUBY_VERSION" 
echo "Erlang Version: $ERLANG_VERSION"
echo "Elixir Version: $ELIXIR_VERSION"
echo "========================================"

# Build from project root
cd "$(dirname "$0")/../.."

# Check if environment image exists, if not provide instructions
if ! docker image inspect "$ENV_IMAGE" >/dev/null 2>&1; then
    echo ""
    echo "❌ Environment image $ENV_IMAGE not found!"
    echo ""
    echo "Build it first with:"
    echo "  ./devops/scripts/build-environment.sh multi v0.18.0 $ERLANG_VERSION $ELIXIR_VERSION $RUBY_VERSION"
    echo ""
    echo "Or with defaults:"
    echo "  ./devops/scripts/build-environment.sh multi"
    echo ""
    exit 1
fi

echo "✅ Environment image $ENV_IMAGE found"

# Create temporary Dockerfile with dynamic FROM
TEMP_DOCKERFILE=$(mktemp)
trap "rm -f $TEMP_DOCKERFILE" EXIT

# Write the base Dockerfile
cat > "$TEMP_DOCKERFILE" << EOF
# Production Dockerfile for Trifle (Generated)
FROM $ENV_IMAGE AS builder

# Set build environment
ENV MIX_ENV=prod

WORKDIR /app

# Copy mix files and install dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# Copy application source code
COPY . .

EOF

# Add asset building commands conditionally
if [[ "$SKIP_ASSETS" != "true" ]]; then
cat >> "$TEMP_DOCKERFILE" << 'ASSETS_EOF'
# Build assets and compile the release
RUN mix assets.setup
RUN mix assets.deploy
RUN mix compile
RUN mix release
ASSETS_EOF
else
cat >> "$TEMP_DOCKERFILE" << 'ASSETS_EOF'
# Assets pre-built locally, skipping asset compilation in Docker
RUN mix compile
RUN mix release
ASSETS_EOF
fi

# Add the runtime stage
cat >> "$TEMP_DOCKERFILE" << 'RUNTIME_EOF'

# Production stage
FROM debian:latest AS runtime

# Install runtime dependencies
RUN apt-get update -y && \
    apt-get install -y \
    libstdc++6 \
    openssl \
    libncurses6 \
    ca-certificates \
    curl \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create app user
RUN useradd --create-home --shell /bin/bash app
USER app
WORKDIR /home/app

# Copy the built release from builder stage
COPY --from=builder --chown=app:app /app/_build/prod/rel/trifle ./

# Set environment variables
ENV MIX_ENV=prod
ENV PHX_SERVER=true

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:4000/api/health || exit 1

# Expose port
EXPOSE 4000

# Start the application
CMD ["./bin/trifle", "start"]
RUNTIME_EOF

echo ""
echo "🔨 Building production image..."

# Build production image using temporary Dockerfile
case "$PLATFORM" in
    "multi")
        echo "Building multi-platform image (AMD64 + ARM64)..."
        
        # Create buildx builder if it doesn't exist
        if ! docker buildx ls | grep -q "multiplatform"; then
            echo "Creating buildx builder..."
            docker buildx create --name multiplatform --driver docker-container --bootstrap
        fi

        # Use the buildx builder
        docker buildx use multiplatform

        # Build and push multi-platform image
        docker buildx build \
            --platform linux/amd64,linux/arm64 \
            -f "$TEMP_DOCKERFILE" \
            -t "$APP_IMAGE_NAME:$APP_TAG" \
            -t "$APP_IMAGE_NAME:latest" \
            --push \
            .
            
        # Also load current platform for local use
        echo ""
        echo "Loading current platform image for local use..."
        CURRENT_PLATFORM=$(docker version --format '{{.Server.Os}}/{{.Server.Arch}}')
        docker buildx build \
            --platform "$CURRENT_PLATFORM" \
            -f "$TEMP_DOCKERFILE" \
            -t "$APP_IMAGE_NAME:$APP_TAG" \
            -t "$APP_IMAGE_NAME:latest" \
            --load \
            .
        ;;
    "amd64")
        echo "Building for AMD64 only..."
        docker build \
            --platform linux/amd64 \
            -f "$TEMP_DOCKERFILE" \
            -t "$APP_IMAGE_NAME:$APP_TAG" \
            -t "$APP_IMAGE_NAME:latest" \
            .
        ;;
    "arm64")
        echo "Building for ARM64 only..."
        docker build \
            --platform linux/arm64 \
            -f "$TEMP_DOCKERFILE" \
            -t "$APP_IMAGE_NAME:$APP_TAG" \
            -t "$APP_IMAGE_NAME:latest" \
            .
        ;;
    *)
        echo "Building for current platform..."
        docker build \
            -f "$TEMP_DOCKERFILE" \
            -t "$APP_IMAGE_NAME:$APP_TAG" \
            -t "$APP_IMAGE_NAME:latest" \
            .
        ;;
esac

echo ""
echo "✅ Successfully built $APP_IMAGE_NAME:$APP_TAG"
echo ""
echo "📦 Image details:"
echo "  - App Image: $APP_IMAGE_NAME:$APP_TAG"
echo "  - App Image: $APP_IMAGE_NAME:latest"
echo "  - Based on: $ENV_IMAGE"

# Optional: Push to registry
if [[ "${PUSH_TO_REGISTRY}" == "true" ]]; then
    echo ""
    echo "📤 Pushing to registry..."
    docker push "$APP_IMAGE_NAME:$APP_TAG"
    docker push "$APP_IMAGE_NAME:latest"
fi

echo ""
echo "🎯 To run this image:"
echo "docker run -p 4000:4000 \\"
echo "  -e SECRET_KEY_BASE=your_secret \\"
echo "  -e DATABASE_URL=your_db_url \\"
echo "  $APP_IMAGE_NAME:$APP_TAG"