#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

: "${SOURCE_ENV_PREFIX:?SOURCE_ENV_PREFIX is required in bridge.env}"
: "${CONDA_PACK_BIN:?CONDA_PACK_BIN is required in bridge.env}"
: "${SOURCE_ENV_ARCHIVE_DIR:?SOURCE_ENV_ARCHIVE_DIR is required in bridge.env}"
: "${ENV_ARCHIVE_NAME:?ENV_ARCHIVE_NAME is required in bridge.env}"
: "${PACK_IGNORE_MISSING:=0}"

require_safe_absolute_path "$SOURCE_ENV_PREFIX" SOURCE_ENV_PREFIX
require_safe_absolute_path "$SOURCE_ENV_ARCHIVE_DIR" SOURCE_ENV_ARCHIVE_DIR
if [[ ! "$ENV_ARCHIVE_NAME" =~ ^[A-Za-z0-9._-]+\.tar\.gz$ ]]; then
    printf 'ENV_ARCHIVE_NAME must end in .tar.gz and contain only safe characters: %s\n' "$ENV_ARCHIVE_NAME" >&2
    exit 4
fi
if [[ ! -x "$CONDA_PACK_BIN" ]]; then
    printf 'conda-pack is not executable: %s\n' "$CONDA_PACK_BIN" >&2
    exit 5
fi
if [[ ! -x "$SOURCE_ENV_PREFIX/bin/python" ]]; then
    printf 'Environment Python not found: %s/bin/python\n' "$SOURCE_ENV_PREFIX" >&2
    exit 5
fi

mkdir -p -- "$SOURCE_ENV_ARCHIVE_DIR"
archive="$SOURCE_ENV_ARCHIVE_DIR/$ENV_ARCHIVE_NAME"
archive_stem="${ENV_ARCHIVE_NAME%.tar.gz}"
partial="$SOURCE_ENV_ARCHIVE_DIR/.${archive_stem}.partial.$$.tar.gz"
trap 'rm -f -- "$partial"' EXIT

pack_args=(-p "$SOURCE_ENV_PREFIX" -o "$partial" --format tar.gz)
if [[ "$PACK_IGNORE_MISSING" == "1" ]]; then
    printf 'WARNING: packing with --ignore-missing-files because PACK_IGNORE_MISSING=1.\n' >&2
    pack_args+=(--ignore-missing-files)
fi

printf 'Packing environment: %s\n' "$SOURCE_ENV_PREFIX"
printf 'Temporary archive: %s\n' "$partial"
"$CONDA_PACK_BIN" "${pack_args[@]}"
mv -f -- "$partial" "$archive"
trap - EXIT

(
    cd -- "$SOURCE_ENV_ARCHIVE_DIR"
    sha256sum "$ENV_ARCHIVE_NAME" > "$ENV_ARCHIVE_NAME.sha256"
)

printf 'Environment archive ready:\n'
ls -lh -- "$archive" "$archive.sha256"
