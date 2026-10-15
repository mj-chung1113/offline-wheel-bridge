#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

: "${SOURCE_WHEELHOUSE:?SOURCE_WHEELHOUSE is required in bridge.env}"
: "${TARGET_TUNNEL_HOST:?TARGET_TUNNEL_HOST is required in bridge.env}"
: "${TARGET_TUNNEL_PORT:?TARGET_TUNNEL_PORT is required in bridge.env}"
: "${TARGET_SSH_USER:?TARGET_SSH_USER is required in bridge.env}"
: "${TARGET_WHEELHOUSE:?TARGET_WHEELHOUSE is required in bridge.env}"

require_command ssh
require_command rsync
require_safe_absolute_path "$SOURCE_WHEELHOUSE" SOURCE_WHEELHOUSE
require_safe_absolute_path "$TARGET_WHEELHOUSE" TARGET_WHEELHOUSE
require_port "$TARGET_TUNNEL_PORT"

if [[ ! -d "$SOURCE_WHEELHOUSE" ]]; then
    printf 'Source wheelhouse does not exist: %s\n' "$SOURCE_WHEELHOUSE" >&2
    exit 5
fi

target="${TARGET_SSH_USER}@${TARGET_TUNNEL_HOST}"
ssh_cmd="ssh -p ${TARGET_TUNNEL_PORT} -o ServerAliveInterval=30 -o ServerAliveCountMax=3"

printf 'Checking tunnel and destination...\n'
ssh -p "$TARGET_TUNNEL_PORT" \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    "$target" \
    "mkdir -p -- '$TARGET_WHEELHOUSE'"

rsync -ah \
    --partial \
    --info=progress2 \
    -e "$ssh_cmd" \
    "$SOURCE_WHEELHOUSE/" \
    "$target:$TARGET_WHEELHOUSE/"

printf 'Sync complete: %s:%s\n' "$target" "$TARGET_WHEELHOUSE"
