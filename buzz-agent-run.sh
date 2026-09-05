#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s AGENT_COMMAND [ARG ...]\n' "$(basename "$0")" >&2
}

[[ $# -ge 1 ]] || { usage; exit 64; }

container_manager=${ADS_CONTAINER_MANAGER:-podman}
runtime_name=${ADS_RUNTIME_NAME:-agentic}

"$container_manager" container exists "$runtime_name" >/dev/null 2>&1 || {
  printf 'Managed Buzz runtime is not running: %s\n' "$runtime_name" >&2
  exit 69
}

exec "$container_manager" exec --interactive --tty "$runtime_name" \
  /home/agent/.local/bin/buzz-agent-create "$@"
