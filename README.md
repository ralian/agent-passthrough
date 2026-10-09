# Cursor Agent Passthrough Container

Run `cursor-agent` in Docker with host credentials mounted **read-only**, and a single host **read-write** bind: your input folder.

## Build

```bash
./docker-build.sh
# or, if your user is not in the docker group:
DOCKER='sudo docker' ./docker-build.sh
```

Image default: `cursor-agent-passthrough:latest`

## Run

```bash
./docker-run.sh <input-dir> [--] [cursor-agent args...]
```

With no agent args, opens an **interactive** `cursor-agent` session (`--trust`) on a TTY. Extra args are passed through and replace that default (e.g. `-p` for one-shot print mode).

| Host path | Container path | Mode |
|-----------|----------------|------|
| `~/.config/cursor` | `/mnt/cursor-creds` | read-only (copied into HOME at start) |
| `<input-dir>` | `/workspace` | read-write |

Outbound network uses the Docker **bridge** by default (not disabled), with public DNS (`8.8.8.8`, `1.1.1.1`). The entrypoint enables HTTP/1.1 for agent API calls. If the model provider is still unreachable, try host networking:

```bash
DOCKER_NETWORK=host ./docker-run.sh ./ws/pygitweb
```

Host `HTTP(S)_PROXY` / `NO_PROXY` / `CURSOR_API_KEY` / `CURSOR_API_ENDPOINT` are forwarded when set.

The container root filesystem is `--read-only`. Writable areas besides `/workspace` are tmpfs (`/tmp`, `/root/.cursor`, `/root/.config`, `/root/.local/share`). The agent binary is at `/opt/cursor-agent`.

### Examples

```bash
# Ensure you are logged in on the host first
cursor-agent login

# Interactive agent shell in ./ws/pygitweb
./docker-run.sh ./ws/pygitweb

# One-shot (non-interactive) prompt
./docker-run.sh ./jobs/demo --trust -p "summarize this repo"

DOCKER='sudo docker' ./docker-run.sh /absolute/path/to/work --list-models
```

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `IMAGE_NAME` | `cursor-agent-passthrough` | Image name |
| `IMAGE_TAG` | `latest` | Image tag |
| `HOST_CURSOR_CONFIG` | `~/.config/cursor` | Host credentials directory |
| `DOCKER_NETWORK` | `bridge` | `bridge` or `host` |
| `DOCKER` | `docker` (or `sudo docker` if needed) | Docker CLI invocation |
