#!/usr/bin/env bash
# Run cursor-agent in a container with:
#   - host Cursor CLI credentials mounted read-only
#   - a single host read-write bind: the given input folder -> /workspace
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-cursor-agent-passthrough}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
IMAGE_REF="${IMAGE_NAME}:${IMAGE_TAG}"

# Default host credential location used by cursor-agent login.
HOST_CURSOR_CONFIG="${HOST_CURSOR_CONFIG:-${HOME}/.config/cursor}"
CONTAINER_CREDS_RO="/mnt/cursor-creds"
CONTAINER_WORKSPACE="/workspace"

# Docker network mode: bridge (default) or host if bridge DNS/routing is broken.
DOCKER_NETWORK="${DOCKER_NETWORK:-bridge}"

usage() {
  cat <<'EOF'
Usage: docker-run.sh <input-dir> [--] [cursor-agent args...]

With no agent args, starts an interactive cursor-agent session (--trust)
in /workspace. Pass args through to override (e.g. -p for one-shot print).

Mounts:
  ~/.config/cursor  -> /mnt/cursor-creds   (read-only; copied to HOME at start)
  <input-dir>       -> /workspace          (read-write; only host RW mount)

Networking:
  Default Docker bridge with public DNS. Outbound HTTPS to api2.cursor.sh is
  required. Set DOCKER_NETWORK=host if bridge DNS/routing fails on your host.
  HTTP(S)_PROXY / NO_PROXY / CURSOR_API_* from the host are passed through.

Environment:
  IMAGE_NAME            Image name (default: cursor-agent-passthrough)
  IMAGE_TAG             Image tag  (default: latest)
  HOST_CURSOR_CONFIG    Host credentials dir (default: ~/.config/cursor)
  DOCKER_NETWORK        bridge|host (default: bridge)
  DOCKER                Docker binary (default: docker, or sudo docker)

Examples:
  ./docker-run.sh ./ws/pygitweb
  DOCKER_NETWORK=host ./docker-run.sh ./ws/pygitweb
  ./docker-run.sh ./jobs/demo --trust -p "summarize this repo"
EOF
}

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
  die "cannot access docker (try: sudo usermod -aG docker \$USER, or DOCKER='sudo docker')"
}

ensure_image() {
  if ! "${DOCKER_CMD[@]}" image inspect "${IMAGE_REF}" >/dev/null 2>&1; then
    die "image ${IMAGE_REF} not found; build with: ./docker-build.sh"
  fi
}

require_credentials() {
  local auth_json="${HOST_CURSOR_CONFIG}/auth.json"
  [[ -d "${HOST_CURSOR_CONFIG}" ]] || die "credentials dir missing: ${HOST_CURSOR_CONFIG}"
  [[ -f "${auth_json}" ]] || die "credentials file missing: ${auth_json} (run: cursor-agent login)"
}

resolve_input_dir() {
  local raw="$1"
  local resolved

  [[ -n "${raw}" ]] || die "input directory is required"
  [[ -d "${raw}" ]] || die "input directory does not exist: ${raw}"
  [[ -r "${raw}" && -w "${raw}" ]] || die "input directory must be readable and writable: ${raw}"

  if command -v realpath >/dev/null 2>&1; then
    resolved="$(realpath "${raw}")"
  else
    resolved="$(cd "${raw}" && pwd -P)"
  fi

  case "${resolved}" in
    "${HOST_CURSOR_CONFIG}"|"${HOST_CURSOR_CONFIG}/"*)
      die "input directory must not be the credentials directory"
      ;;
  esac

  printf '%s\n' "${resolved}"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi
  [[ $# -ge 1 ]] || {
    usage >&2
    exit 1
  }

  local input_raw="$1"
  shift
  if [[ "${1:-}" == "--" ]]; then
    shift
  fi

  resolve_docker
  ensure_image
  require_credentials

  local input_dir
  input_dir="$(resolve_input_dir "${input_raw}")"

  local -a agent_args=("$@")
  if [[ ${#agent_args[@]} -eq 0 ]]; then
    agent_args=(--trust)
  fi

  local -a run_flags=(--rm)
  if [[ -t 0 && -t 1 ]]; then
    run_flags+=(-it)
  else
    run_flags+=(-i)
  fi

  local -a net_flags=(--network "${DOCKER_NETWORK}")
  if [[ "${DOCKER_NETWORK}" == "bridge" ]]; then
    # Avoid broken host stub resolvers (e.g. 127.0.0.53) inside the bridge namespace.
    net_flags+=(--dns 8.8.8.8 --dns 1.1.1.1)
  fi

  local -a env_flags=()
  local var
  for var in \
    HTTP_PROXY HTTPS_PROXY NO_PROXY \
    http_proxy https_proxy no_proxy \
    CURSOR_API_KEY CURSOR_API_ENDPOINT; do
    if [[ -n "${!var:-}" ]]; then
      env_flags+=(-e "${var}=${!var}")
    fi
  done

  # Root filesystem is read-only; only /workspace is a host RW bind.
  # Credentials stay read-only on the host; entrypoint copies them into a
  # tmpfs-backed HOME path so token refresh can succeed inside the container.
  exec "${DOCKER_CMD[@]}" run "${run_flags[@]}" \
    "${net_flags[@]}" \
    "${env_flags[@]}" \
    --read-only \
    --tmpfs /tmp:rw,mode=1777 \
    --tmpfs /root/.cursor:rw,mode=0700 \
    --tmpfs /root/.config:rw,mode=0700 \
    --tmpfs /root/.local/share:rw,mode=0700 \
    --mount "type=bind,src=${HOST_CURSOR_CONFIG},dst=${CONTAINER_CREDS_RO},readonly=true" \
    --mount "type=bind,src=${input_dir},dst=${CONTAINER_WORKSPACE},readonly=false" \
    -w "${CONTAINER_WORKSPACE}" \
    "${IMAGE_REF}" \
    "${agent_args[@]}"
}

main "$@"
