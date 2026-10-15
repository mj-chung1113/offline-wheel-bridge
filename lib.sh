#!/usr/bin/env bash

set -euo pipefail

BRIDGE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_CONFIG="${BRIDGE_CONFIG:-$BRIDGE_DIR/bridge.conf}"

if [[ ! -f "$BRIDGE_CONFIG" ]]; then
    printf 'Configuration not found: %s\n' "$BRIDGE_CONFIG" >&2
    printf 'Copy bridge.conf.example to bridge.conf and edit it first.\n' >&2
    exit 2
fi

# shellcheck disable=SC1090
source "$BRIDGE_CONFIG"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$1" >&2
        exit 3
    fi
}

require_safe_absolute_path() {
    local value="$1"
    local label="$2"
    if [[ ! "$value" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
        printf '%s must be a simple absolute path: %s\n' "$label" "$value" >&2
        exit 4
    fi
}

require_port() {
    local value="$1"
    if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 1 || value > 65535 )); then
        printf 'Invalid TCP port: %s\n' "$value" >&2
        exit 4
    fi
}
