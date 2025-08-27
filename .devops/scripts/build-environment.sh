#!/bin/bash

# 🏗️  THE ONE SCRIPT TO RULE THEM ALL 🏗️
# Build Trifle environment image with dynamic versions and multi-platform support
# Usage: ./build-environment.sh [platform] [asdf_version] [erlang_version] [elixir_version] [ruby_version]
# 
# Examples:
#   ./build-environment.sh multi                           # All defaults
#   ./build-environment.sh amd64 v0.18.0 28.0.2 1.18.4     # AMD64 with custom versions  
#   ./build-environment.sh multi v0.17.0 27.3 1.17.3 3.1.4 # Multi-platform with old versions

set -e

# Parse arguments with defaults
PLATFORM=${1:-multi}
ASDF_VERSION=${2:-v0.18.0}
ERLANG_VERSION=${3:-28.0.2}
ELIXIR_VERSION=${4:-1.18.4}
RUBY_VERSION=${5:-3.2.0}

IMAGE_NAME="trifle/environment"

# Generate dynamic tag from versions
generate_tag() {
    local ruby_v="$1"
    local erlang_v="$2" 
    local elixir_v="$3"
    echo "ruby_${ruby_v}-erlang_${erlang_v}-elixir_${elixir_v}"
}

DYNAMIC_TAG=$(generate_tag "$RUBY_VERSION" "$ERLANG_VERSION" "$ELIXIR_VERSION")

echo "========================================"
echo "Building Environment Image"
echo "========================================"
echo "Platform: $PLATFORM"
echo "ASDF Version: $ASDF_VERSION"
echo "Ruby Version: $RUBY_VERSION" 
echo "Erlang Version: $ERLANG_VERSION"
echo "Elixir Version: $ELIXIR_VERSION"
echo "Image Tag: $IMAGE_NAME:$DYNAMIC_TAG"
echo "========================================"

cd "$(dirname "$0")/../docker/environment"

case "$PLATFORM" in
    "amd64")
        echo "Building for AMD64 only..."
        docker build \
            --platform linux/amd64 \
            --build-arg ASDF_VERSION="$ASDF_VERSION" \
            --build-arg ERLANG_VERSION="$ERLANG_VERSION" \
            --build-arg ELIXIR_VERSION="$ELIXIR_VERSION" \
            --build-arg RUBY_VERSION="$RUBY_VERSION" \
            -t "$IMAGE_NAME:$DYNAMIC_TAG" \
            -t "$IMAGE_NAME:latest-amd64" \
            .
        ;;
    "arm64")
        echo "Building for ARM64 only..."
        docker build \
            --platform linux/arm64 \
            --build-arg ASDF_VERSION="$ASDF_VERSION" \
            --build-arg ERLANG_VERSION="$ERLANG_VERSION" \
            --build-arg ELIXIR_VERSION="$ELIXIR_VERSION" \
            --build-arg RUBY_VERSION="$RUBY_VERSION" \
            -t "$IMAGE_NAME:$DYNAMIC_TAG" \
            -t "$IMAGE_NAME:latest-arm64" \
            .
        ;;
    "multi")
        echo "Building for multiple platforms (AMD64 + ARM64)..."
        
        # Create buildx builder if it doesn't exist
        if ! docker buildx ls | grep -q "multiplatform"; then
            echo "Creating buildx builder..."
            docker buildx create --name multiplatform --driver docker-container --bootstrap
        fi

        # Use the buildx builder
        docker buildx use multiplatform

        # For multi-platform, we need to push to registry (Docker limitation)
        echo "Building and pushing multi-platform image to registry..."
        echo "Registry: $IMAGE_NAME"
        
        docker buildx build \
            --platform linux/amd64,linux/arm64 \
            --build-arg ASDF_VERSION="$ASDF_VERSION" \
            --build-arg ERLANG_VERSION="$ERLANG_VERSION" \
            --build-arg ELIXIR_VERSION="$ELIXIR_VERSION" \
            --build-arg RUBY_VERSION="$RUBY_VERSION" \
            -t "$IMAGE_NAME:$DYNAMIC_TAG" \
            -t "$IMAGE_NAME:latest" \
            --push \
            .
            
        # Also load the current platform for local use
        echo ""
        echo "Loading current platform image for local use..."
        CURRENT_PLATFORM=$(docker version --format '{{.Server.Os}}/{{.Server.Arch}}')
        docker buildx build \
            --platform "$CURRENT_PLATFORM" \
            --build-arg ASDF_VERSION="$ASDF_VERSION" \
            --build-arg ERLANG_VERSION="$ERLANG_VERSION" \
            --build-arg ELIXIR_VERSION="$ELIXIR_VERSION" \
            --build-arg RUBY_VERSION="$RUBY_VERSION" \
            -t "$IMAGE_NAME:$DYNAMIC_TAG" \
            -t "$IMAGE_NAME:latest" \
            --load \
            .
        ;;
    *)
        echo "Usage: $0 {amd64|arm64|multi} [asdf_version] [erlang_version] [elixir_version] [ruby_version]"
        echo ""
        echo "Arguments (all optional with defaults):"
        echo "  platform      - amd64, arm64, or multi (default: multi)"
        echo "  asdf_version  - ASDF version (default: v0.18.0)"
        echo "  erlang_version- Erlang version (default: 28.0.2)"
        echo "  elixir_version- Elixir version (default: 1.18.4)"  
        echo "  ruby_version  - Ruby version (default: 3.2.0)"
        echo ""
        echo "Examples:"
        echo "  $0 multi                                    # All defaults"
        echo "  $0 amd64 v0.17.0                           # AMD64 with ASDF v0.17.0"
        echo "  $0 multi v0.18.0 27.3 1.17.3 3.1.4         # Custom versions"
        exit 1
        ;;
esac

echo ""
echo "✅ Successfully built $IMAGE_NAME:$DYNAMIC_TAG for $PLATFORM"
echo ""
echo "Image tags created:"
echo "  - $IMAGE_NAME:$DYNAMIC_TAG"
if [[ "$PLATFORM" != "multi" ]]; then
    echo "  - $IMAGE_NAME:latest-$PLATFORM"
else
    echo "  - $IMAGE_NAME:latest"
fi

# Optional: Push single-platform images to registry  
if [[ "${PUSH_TO_REGISTRY}" == "true" && "$PLATFORM" != "multi" ]]; then
    echo ""
    echo "📤 Pushing single-platform image to registry..."
    docker push "$IMAGE_NAME:$DYNAMIC_TAG"
    if [[ "$PLATFORM" == "amd64" ]]; then
        docker push "$IMAGE_NAME:latest-amd64"
    else
        docker push "$IMAGE_NAME:latest-arm64"
    fi
fi

echo ""
echo "To use this image in your Dockerfiles:"
echo "FROM $IMAGE_NAME:$DYNAMIC_TAG"