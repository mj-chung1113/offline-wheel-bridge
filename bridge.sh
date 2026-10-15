#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if (( $# == 0 )); then
    printf 'Usage: %s PACKAGE...\n' "$0" >&2
    printf '   or: %s -r requirements.txt\n' "$0" >&2
    exit 2
fi

"$SCRIPT_DIR/download-wheels.sh" "$@"
"$SCRIPT_DIR/sync-wheelhouse.sh"
