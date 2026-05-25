#!/usr/bin/env bash

set -euo pipefail

# Build the Trifle private connector image.
# Usage: ./.devops/scripts/build-connector.sh [tag] [platform] [image_name]
#
# Examples:
#   ./.devops/scripts/build-connector.sh
#   ./.devops/scripts/build-connector.sh 0.15.0 amd64
#   ./.devops/scripts/build-connector.sh 0.15.0 multi trifle/connector

TAG="${1:-latest}"
PLATFORM="${2:-current}"
IMAGE_NAME="${3:-trifle/connector}"

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CONTEXT_DIR="$ROOT_DIR/connector"
DOCKERFILE="$ROOT_DIR/.devops/docker/connector/Dockerfile"

if [[ -f "$ROOT_DIR/VERSION" ]]; then
  VERSION="${VERSION:-$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")}"
else
  VERSION="${VERSION:-dev}"
fi

COMMIT="${COMMIT:-$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)}"
BUILD_DATE="${BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

TAGS=(-t "$IMAGE_NAME:$TAG")
if [[ "$TAG" != "latest" ]]; then
  TAGS+=(-t "$IMAGE_NAME:latest")
fi

COMMON_ARGS=(
  -f "$DOCKERFILE"
  "${TAGS[@]}"
  --build-arg "VERSION=$VERSION"
  --build-arg "COMMIT=$COMMIT"
  --build-arg "BUILD_DATE=$BUILD_DATE"
)

echo "Building Trifle connector image"
echo "Image: $IMAGE_NAME:$TAG"
echo "Platform: $PLATFORM"
echo "Version: $VERSION"
echo "Commit: $COMMIT"
echo "Build date: $BUILD_DATE"

case "$PLATFORM" in
  current)
    docker build "${COMMON_ARGS[@]}" "$CONTEXT_DIR"
    ;;
  amd64)
    docker build --platform linux/amd64 "${COMMON_ARGS[@]}" "$CONTEXT_DIR"
    ;;
  arm64)
    docker build --platform linux/arm64 "${COMMON_ARGS[@]}" "$CONTEXT_DIR"
    ;;
  multi)
    if ! docker buildx ls | grep -q "trifle-connector-builder"; then
      docker buildx create --name trifle-connector-builder --driver docker-container --bootstrap
    fi

    docker buildx build \
      --builder trifle-connector-builder \
      --platform linux/amd64,linux/arm64 \
      "${COMMON_ARGS[@]}" \
      --push \
      "$CONTEXT_DIR"
    ;;
  *)
    echo "Unsupported platform: $PLATFORM" >&2
    echo "Use current, amd64, arm64, or multi." >&2
    exit 1
    ;;
esac

echo "Built $IMAGE_NAME:$TAG"
