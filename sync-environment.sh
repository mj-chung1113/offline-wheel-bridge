#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

: "${SOURCE_ENV_ARCHIVE_DIR:?SOURCE_ENV_ARCHIVE_DIR is required in bridge.env}"
: "${ENV_ARCHIVE_NAME:?ENV_ARCHIVE_NAME is required in bridge.env}"
: "${TARGET_ENV_ARCHIVE_DIR:?TARGET_ENV_ARCHIVE_DIR is required in bridge.env}"
: "${TARGET_TUNNEL_HOST:?TARGET_TUNNEL_HOST is required in bridge.env}"
: "${TARGET_TUNNEL_PORT:?TARGET_TUNNEL_PORT is required in bridge.env}"
: "${TARGET_SSH_USER:?TARGET_SSH_USER is required in bridge.env}"

require_command ssh
require_command rsync
require_safe_absolute_path "$SOURCE_ENV_ARCHIVE_DIR" SOURCE_ENV_ARCHIVE_DIR
require_safe_absolute_path "$TARGET_ENV_ARCHIVE_DIR" TARGET_ENV_ARCHIVE_DIR
require_port "$TARGET_TUNNEL_PORT"
if [[ ! "$ENV_ARCHIVE_NAME" =~ ^[A-Za-z0-9._-]+\.tar\.gz$ ]]; then
    printf 'Unsafe ENV_ARCHIVE_NAME: %s\n' "$ENV_ARCHIVE_NAME" >&2
    exit 4
fi

archive="$SOURCE_ENV_ARCHIVE_DIR/$ENV_ARCHIVE_NAME"
checksum="$archive.sha256"
if [[ ! -f "$archive" || ! -f "$checksum" ]]; then
    printf 'Archive or checksum missing. Run pack-environment.sh first.\n' >&2
    exit 5
fi

target="${TARGET_SSH_USER}@${TARGET_TUNNEL_HOST}"
ssh_cmd="ssh -p ${TARGET_TUNNEL_PORT} -o ServerAliveInterval=30 -o ServerAliveCountMax=3"

ssh -p "$TARGET_TUNNEL_PORT" \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    "$target" \
    "mkdir -p -- '$TARGET_ENV_ARCHIVE_DIR'"

rsync -ah \
    --partial \
    --info=progress2 \
    -e "$ssh_cmd" \
    "$archive" \
    "$checksum" \
    "$target:$TARGET_ENV_ARCHIVE_DIR/"

printf 'Environment archive sync complete: %s:%s/%s\n' \
    "$target" "$TARGET_ENV_ARCHIVE_DIR" "$ENV_ARCHIVE_NAME"
