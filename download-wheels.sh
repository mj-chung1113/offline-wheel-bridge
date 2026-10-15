#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

: "${PYTHON_BIN:?PYTHON_BIN is required in bridge.conf}"
: "${SOURCE_WHEELHOUSE:?SOURCE_WHEELHOUSE is required in bridge.conf}"
: "${BINARY_ONLY:=0}"

require_safe_absolute_path "$SOURCE_WHEELHOUSE" SOURCE_WHEELHOUSE
if [[ ! -x "$PYTHON_BIN" ]]; then
    printf 'Python is not executable: %s\n' "$PYTHON_BIN" >&2
    exit 5
fi
if (( $# == 0 )); then
    printf 'Usage: %s PACKAGE...\n' "$0" >&2
    printf '   or: %s -r requirements.txt\n' "$0" >&2
    exit 2
fi

mkdir -p -- "$SOURCE_WHEELHOUSE"
pip_args=(download --dest "$SOURCE_WHEELHOUSE")
if [[ "$BINARY_ONLY" == "1" ]]; then
    pip_args+=(--only-binary=:all:)
fi

printf 'Downloader: %s\n' "$PYTHON_BIN"
"$PYTHON_BIN" -c 'import platform,sys; print("Python:", sys.version.split()[0]); print("Platform:", platform.platform())'
"$PYTHON_BIN" -m pip "${pip_args[@]}" "$@"

(
    cd -- "$SOURCE_WHEELHOUSE"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\0' \
        | sort -z \
        | xargs -0 -r sha256sum > SHA256SUMS
)

printf 'Wheelhouse updated: %s\n' "$SOURCE_WHEELHOUSE"
du -sh -- "$SOURCE_WHEELHOUSE"
