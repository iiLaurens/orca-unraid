#!/usr/bin/env bash
# Builds the local image the Unraid template references. Run on the Docker host, not on Windows.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

ORCA_VERSION=${ORCA_VERSION:-latest}
PI_VERSION=${PI_VERSION:-latest}
IMAGE=${IMAGE:-orca-server:local}

# Docker would otherwise reuse the install layer for "latest" forever.
if [ -z "${BUILD_REFRESH:-}" ]; then
  if [ "$ORCA_VERSION" = "latest" ] || [ "$PI_VERSION" = "latest" ]; then
    BUILD_REFRESH=$(date +%s)
  else
    BUILD_REFRESH=0
  fi
fi

docker build \
  --build-arg "ORCA_VERSION=${ORCA_VERSION}" \
  --build-arg "PI_VERSION=${PI_VERSION}" \
  --build-arg "BUILD_REFRESH=${BUILD_REFRESH}" \
  --tag "$IMAGE" \
  "$@" \
  .
