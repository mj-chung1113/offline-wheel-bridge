#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/bridge.conf"
REPLACE=0
IGNORE_MISSING=0

usage() {
    cat <<'EOF'
Usage:
  ./deploy-conda-env.sh [--config FILE] [--replace] [--ignore-missing] ENV_NAME

Options:
  --config FILE      Use another configuration file.
  --replace          Back up and replace an existing remote environment.
  --ignore-missing   Pass --ignore-missing-files to conda-pack.
  -h, --help         Show this help.
EOF
}

while (($#)); do
    case "$1" in
        --config)
            [[ $# -ge 2 ]] || { printf '%s\n' '--config requires a file.' >&2; exit 2; }
            CONFIG_PATH="$2"
            shift 2
            ;;
        --replace)
            REPLACE=1
            shift
            ;;
        --ignore-missing)
            IGNORE_MISSING=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
        *)
            [[ -z "${ENV_NAME:-}" ]] || { printf '%s\n' 'Only one environment name is allowed.' >&2; exit 2; }
            ENV_NAME="$1"
            shift
            ;;
    esac
done

[[ -n "${ENV_NAME:-}" ]] || { usage >&2; exit 2; }
[[ "$ENV_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || {
    printf 'Unsafe environment name: %s\n' "$ENV_NAME" >&2
    exit 2
}
[[ -f "$CONFIG_PATH" ]] || {
    printf 'Configuration not found: %s\n' "$CONFIG_PATH" >&2
    printf '%s\n' 'Copy bridge.conf.example to bridge.conf and edit required values.' >&2
    exit 2
}

# shellcheck disable=SC1090
source "$CONFIG_PATH"

required=(
    TUNNEL_HOST TUNNEL_PORT REMOTE_USER SOURCE_CONDA_ROOT CONDA_PACK_BIN
    LOCAL_ARCHIVE_DIR REMOTE_ARCHIVE_DIR REMOTE_CONDA_ROOT
)
for key in "${required[@]}"; do
    value="${!key:-}"
    if [[ -z "$value" || "$value" == \[* ]]; then
        printf 'Set %s in %s\n' "$key" "$CONFIG_PATH" >&2
        exit 2
    fi
done

for command_name in ssh rsync sha256sum; do
    command -v "$command_name" >/dev/null 2>&1 || {
        printf 'Required command not found: %s\n' "$command_name" >&2
        exit 3
    }
done
[[ -x "$CONDA_PACK_BIN" ]] || { printf 'conda-pack is not executable: %s\n' "$CONDA_PACK_BIN" >&2; exit 3; }
[[ "$TUNNEL_PORT" =~ ^[0-9]+$ ]] || { printf 'Invalid TUNNEL_PORT: %s\n' "$TUNNEL_PORT" >&2; exit 3; }

source_env="$SOURCE_CONDA_ROOT/envs/$ENV_NAME"
[[ -x "$source_env/bin/python" ]] || {
    printf 'Source environment not found: %s\n' "$source_env" >&2
    exit 4
}

mkdir -p -- "$LOCAL_ARCHIVE_DIR"
archive="$LOCAL_ARCHIVE_DIR/$ENV_NAME.tar.gz"
partial="$LOCAL_ARCHIVE_DIR/.$ENV_NAME.partial.$$.tar.gz"
checksum="$archive.sha256"
trap 'rm -f -- "$partial"' EXIT

pack_args=(-p "$source_env" -o "$partial" --format tar.gz)
if ((IGNORE_MISSING)); then
    pack_args+=(--ignore-missing-files)
    printf '%s\n' 'WARNING: conda-pack will ignore missing/overwritten conda-managed files.' >&2
fi

printf '[1/4] Packing %s\n' "$source_env"
"$CONDA_PACK_BIN" "${pack_args[@]}"
mv -f -- "$partial" "$archive"
trap - EXIT
(
    cd -- "$LOCAL_ARCHIVE_DIR"
    sha256sum "$(basename -- "$archive")" > "$(basename -- "$checksum")"
)

remote="${REMOTE_USER}@${TUNNEL_HOST}"
ssh_options=(-p "$TUNNEL_PORT" -o ServerAliveInterval=30 -o ServerAliveCountMax=3)
ssh_command="ssh -p $TUNNEL_PORT -o ServerAliveInterval=30 -o ServerAliveCountMax=3"
remote_archive="$REMOTE_ARCHIVE_DIR/$ENV_NAME.tar.gz"

printf '[2/4] Checking tunnel and remote conda\n'
ssh "${ssh_options[@]}" "$remote" \
    "test -x '$REMOTE_CONDA_ROOT/bin/conda' && mkdir -p '$REMOTE_ARCHIVE_DIR' '$REMOTE_CONDA_ROOT/envs'" || {
    printf 'Remote conda was not found at %s, or the tunnel is unavailable.\n' "$REMOTE_CONDA_ROOT" >&2
    exit 5
}

printf '[3/4] Transferring archive through the reverse tunnel\n'
rsync -ah --partial --info=progress2 \
    -e "$ssh_command" \
    "$archive" "$checksum" \
    "$remote:$REMOTE_ARCHIVE_DIR/"

printf '[4/4] Installing and validating remote environment\n'
ssh "${ssh_options[@]}" "$remote" bash -s -- \
    "$remote_archive" "$REMOTE_CONDA_ROOT" "$ENV_NAME" "$REPLACE" "${SMOKE_IMPORTS:-}" <<'REMOTE_SCRIPT'
set -euo pipefail

archive="$1"
conda_root="$2"
env_name="$3"
replace="$4"
smoke_imports="$5"
checksum="$archive.sha256"
target="$conda_root/envs/$env_name"
staging="$conda_root/envs/.$env_name.staging.$$"
backup=""
deployed=0
success=0

cleanup() {
    if ((success == 0)); then
        if ((deployed == 1)) && [[ -d "$target" ]]; then
            rm -rf -- "$target"
        fi
        if [[ -n "$backup" && -d "$backup" ]]; then
            mv -- "$backup" "$target"
            printf 'Restored previous environment: %s\n' "$target" >&2
        fi
        if [[ -d "$staging" ]]; then
            rm -rf -- "$staging"
        fi
    fi
}
trap cleanup EXIT

[[ -f "$archive" && -f "$checksum" ]] || {
    printf 'Remote archive or checksum is missing: %s\n' "$archive" >&2
    exit 10
}
(
    cd -- "$(dirname -- "$archive")"
    sha256sum -c "$(basename -- "$checksum")"
)

if [[ -e "$target" && "$replace" != "1" ]]; then
    printf 'Remote environment already exists: %s\n' "$target" >&2
    printf '%s\n' 'Run again with --replace to back it up and replace it.' >&2
    exit 11
fi

mkdir -p -- "$staging"
tar -xzf "$archive" -C "$staging"
[[ -x "$staging/bin/conda-unpack" && -x "$staging/bin/python" ]]

if [[ -e "$target" ]]; then
    backup="$target.backup.$(date +%Y%m%d-%H%M%S)"
    mv -- "$target" "$backup"
    printf 'Previous environment backed up to: %s\n' "$backup"
fi

mv -- "$staging" "$target"
deployed=1
"$target/bin/conda-unpack"
"$target/bin/python" --version
"$target/bin/python" -m pip --version

if [[ -n "$smoke_imports" ]]; then
    IFS=',' read -r -a modules <<< "$smoke_imports"
    for module in "${modules[@]}"; do
        [[ "$module" =~ ^[A-Za-z_][A-Za-z0-9_.]*$ ]] || {
            printf 'Unsafe SMOKE_IMPORTS entry: %s\n' "$module" >&2
            exit 12
        }
        "$target/bin/python" -c "import $module; print('$module: OK')"
    done
fi

success=1
printf 'Deployment complete: %s\n' "$target"
printf 'Activate with: conda activate %s\n' "$env_name"
REMOTE_SCRIPT

printf '\nDone. Remote environment: %s/envs/%s\n' "$REMOTE_CONDA_ROOT" "$ENV_NAME"
