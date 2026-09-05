#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s CHANNEL_UUID DISPLAY_NAME SYSTEM_PROMPT\n' "$(basename "$0")" >&2
}

[[ $# -eq 3 ]] || { usage; exit 64; }
channel_id=$1
display_name=$2
system_prompt=$3

[[ $channel_id =~ ^[0-9a-fA-F-]{36}$ ]] || {
  printf 'Invalid channel UUID: %s\n' "$channel_id" >&2
  exit 64
}
[[ -n $display_name && -n $system_prompt ]] || {
  printf 'Display name and system prompt cannot be empty\n' >&2
  exit 64
}

container_manager=${ADS_CONTAINER_MANAGER:-podman}
runtime_name=${ADS_RUNTIME_NAME:-agentic}

"$container_manager" container exists "$runtime_name" >/dev/null 2>&1 || {
  printf 'Managed Buzz runtime is not running: %s\n' "$runtime_name" >&2
  exit 69
}

exec "$container_manager" exec "$runtime_name" buzz agents draft-create \
  --channel "$channel_id" \
  --display-name "$display_name" \
  --system-prompt "$system_prompt"
