# Public uv base (dhi.io requires authenticated pulls).
FROM ghcr.io/astral-sh/uv:debian-slim

# Cursor Agent installer expects a writable HOME under ~/.local.
ENV HOME=/root \
    PATH="/opt/cursor-agent:/usr/local/bin:${PATH}" \
    CURSOR_CREDS_RO=/mnt/cursor-creds

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://cursor.com/install | bash \
    && test -x /root/.local/bin/cursor-agent \
    && AGENT_SRC="$(readlink -f /root/.local/bin/cursor-agent)" \
    && mkdir -p /opt/cursor-agent \
    && cp -a "$(dirname "${AGENT_SRC}")"/. /opt/cursor-agent/ \
    && test -x /opt/cursor-agent/cursor-agent \
    && ln -sf /opt/cursor-agent/cursor-agent /usr/local/bin/cursor-agent \
    && ln -sf /opt/cursor-agent/cursor-agent /usr/local/bin/agent

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Host credentials are bind-mounted read-only at /mnt/cursor-creds.
# Workspace is bind-mounted read-write at /workspace (only host RW mount).
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
# Interactive agent shell; --trust skips the workspace trust prompt.
CMD ["--trust"]
