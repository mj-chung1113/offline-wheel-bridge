#!/usr/bin/env bash

set -euo pipefail

archive="${1:-/shared/offline-wheel-bridge/env-archives/research-env.tar.gz}"
target="${2:-$HOME/envs/research-cu126}"

safe_path_regex='^/[A-Za-z0-9._/-]+$'
if [[ ! "$archive" =~ $safe_path_regex || ! "$target" =~ $safe_path_regex ]]; then
    printf 'Archive and target must be simple absolute paths.\n' >&2
    exit 4
fi
if [[ ! -f "$archive" ]]; then
    printf 'Archive not found: %s\n' "$archive" >&2
    exit 5
fi
if [[ -e "$target" ]] && [[ -n "$(find "$target" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    printf 'Target already exists and is not empty: %s\n' "$target" >&2
    printf 'Choose a new target. This script never overwrites an existing environment.\n' >&2
    exit 6
fi

checksum="$archive.sha256"
if [[ -f "$checksum" ]]; then
    printf 'Verifying environment archive checksum...\n'
    (
        cd -- "$(dirname -- "$archive")"
        sha256sum -c "$(basename -- "$checksum")"
    )
else
    printf 'WARNING: checksum file not found: %s\n' "$checksum" >&2
fi

mkdir -p -- "$target"
printf 'Extracting environment to: %s\n' "$target"
tar -xzf "$archive" -C "$target"

if [[ ! -x "$target/bin/conda-unpack" ]]; then
    printf 'conda-unpack not found after extraction: %s/bin/conda-unpack\n' "$target" >&2
    exit 7
fi

"$target/bin/conda-unpack"
printf 'Environment ready. Smoke test:\n'
"$target/bin/python" -c 'import sys; print(sys.executable); print(sys.version)'
printf 'Use directly: %s/bin/python YOUR_SCRIPT.py\n' "$target"
