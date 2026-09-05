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

env_file=${ADS_BUZZ_ENV_FILE:-"$HOME/.ads-buzz-env"}
[[ -r $env_file ]] || {
  printf 'Buzz credentials are not configured: %s\n' "$env_file" >&2
  exit 78
}
# shellcheck disable=SC1090
. "$env_file"
: "${BUZZ_RELAY_URL:?BUZZ_RELAY_URL is required}"
: "${BUZZ_PRIVATE_KEY:?BUZZ_PRIVATE_KEY is required}"
: "${BUZZ_AUTH_TAG:?BUZZ_AUTH_TAG is required for owner-reviewed drafts}"

exec buzz agents draft-create \
  --channel "$channel_id" \
  --display-name "$display_name" \
  --system-prompt "$system_prompt"
