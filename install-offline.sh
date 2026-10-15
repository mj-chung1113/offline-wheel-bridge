#!/usr/bin/env bash

set -euo pipefail

WHEELHOUSE_DIR="${WHEELHOUSE_DIR:-/shared/offline-wheel-bridge/wheelhouse}"
PYTHON_BIN="${PYTHON_BIN:-python}"

if [[ ! "$WHEELHOUSE_DIR" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
    printf 'WHEELHOUSE_DIR must be a simple absolute path: %s\n' "$WHEELHOUSE_DIR" >&2
    exit 4
fi
if [[ ! -x "$(command -v "$PYTHON_BIN" 2>/dev/null || true)" && ! -x "$PYTHON_BIN" ]]; then
    printf 'Python is not executable: %s\n' "$PYTHON_BIN" >&2
    exit 5
fi
if (( $# == 0 )); then
    printf 'Usage: %s PACKAGE...\n' "$0" >&2
    printf '   or: %s -r requirements.txt\n' "$0" >&2
    printf 'Optional: PYTHON_BIN=/path/to/python WHEELHOUSE_DIR=/path/to/wheels %s ...\n' "$0" >&2
    exit 2
fi
if [[ ! -d "$WHEELHOUSE_DIR" ]]; then
    printf 'Wheelhouse not found: %s\n' "$WHEELHOUSE_DIR" >&2
    exit 5
fi

if [[ -f "$WHEELHOUSE_DIR/SHA256SUMS" ]]; then
    printf 'Verifying wheelhouse checksums...\n'
    (cd -- "$WHEELHOUSE_DIR" && sha256sum -c SHA256SUMS)
fi

"$PYTHON_BIN" -m pip install \
    --no-index \
    --find-links="$WHEELHOUSE_DIR" \
    "$@"
