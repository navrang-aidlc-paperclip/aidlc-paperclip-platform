#!/bin/sh
# Runs as root before upstream docker-entrypoint.sh drops to the `node` user.
# Responsibilities:
#   1. make sure the workspaces root exists on the volume and is owned by node
#   2. bootstrap/refresh the aidlc-workspace checkout as the node user
#   3. hand over to the upstream entrypoint (UID remap, chown, gosu node CMD)
set -e

root="${AIDLC_WORKSPACES_ROOT:-/paperclip/workspaces}"
mkdir -p "$root"
chown node:node "$root" 2>/dev/null || true

if [ "${AIDLC_BOOTSTRAP_ON_START:-1}" = "1" ]; then
  if [ "$(id -u)" -eq 0 ]; then
    gosu node /usr/local/bin/aidlc-bootstrap-workspace || \
      echo "aidlc-entrypoint: workspace bootstrap failed; server starts anyway, conductor runs will retry" >&2
  else
    /usr/local/bin/aidlc-bootstrap-workspace || \
      echo "aidlc-entrypoint: workspace bootstrap failed; server starts anyway, conductor runs will retry" >&2
  fi
fi

exec /usr/local/bin/docker-entrypoint.sh "$@"
