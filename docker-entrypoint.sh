#!/bin/sh
# Copy host credentials from the read-only mount into a writable HOME path
# so cursor-agent can refresh tokens without mutating the host bind.
set -eu

CREDS_RO="${CURSOR_CREDS_RO:-/mnt/cursor-creds}"
CREDS_RW="${HOME}/.config/cursor"

if [ ! -f "${CREDS_RO}/auth.json" ]; then
  echo "error: missing ${CREDS_RO}/auth.json (read-only credentials mount)" >&2
  exit 1
fi

mkdir -p "${CREDS_RW}"
cp -a "${CREDS_RO}/." "${CREDS_RW}/"

# Prefer HTTP/1.1 inside Docker; HTTP/2 to api2.cursor.sh is a common failure mode.
if [ ! -f "${HOME}/.cursor/cli-config.json" ]; then
  mkdir -p "${HOME}/.cursor"
  cat >"${HOME}/.cursor/cli-config.json" <<'EOF'
{
  "version": 1,
  "network": { "useHttp1ForAgent": true },
  "sandbox": { "mode": "disabled" }
}
EOF
fi

exec /opt/cursor-agent/cursor-agent "$@"
