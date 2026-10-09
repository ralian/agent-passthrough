#!/usr/bin/env bash
# Build the cursor-agent passthrough image.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-cursor-agent-passthrough}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
IMAGE_REF="${IMAGE_NAME}:${IMAGE_TAG}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

resolve_docker() {
  if [[ -n "${DOCKER:-}" ]]; then
    # shellcheck disable=SC2206
    DOCKER_CMD=(${DOCKER})
    return
  fi
  if docker info >/dev/null 2>&1; then
    DOCKER_CMD=(docker)
    return
  fi
  if command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
    DOCKER_CMD=(sudo docker)
    return
  fi
  die "cannot access docker (try: DOCKER='sudo docker' ./docker-build.sh)"
}

resolve_docker
cd "${SCRIPT_DIR}"

"${DOCKER_CMD[@]}" build -t "${IMAGE_REF}" -f Dockerfile .
printf 'built %s\n' "${IMAGE_REF}"
