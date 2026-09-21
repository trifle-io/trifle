#!/usr/bin/env bash
set -euo pipefail
TAG="${1:-latest}"
PLATFORM="${2:-current}"
IMAGE_NAME="${3:-trifle/network-gateway}"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ARGS=(-f "$ROOT_DIR/.devops/docker/network-gateway/Dockerfile" -t "$IMAGE_NAME:$TAG")
case "$PLATFORM" in
  current) docker build "${ARGS[@]}" "$ROOT_DIR/network-gateway" ;;
  amd64|arm64) docker build --platform "linux/$PLATFORM" "${ARGS[@]}" "$ROOT_DIR/network-gateway" ;;
  multi) docker buildx build --platform linux/amd64,linux/arm64 "${ARGS[@]}" --push "$ROOT_DIR/network-gateway" ;;
  *) echo 'Platform must be current, amd64, arm64 or multi' >&2; exit 1 ;;
esac
