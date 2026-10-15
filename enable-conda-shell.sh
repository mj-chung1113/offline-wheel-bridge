#!/usr/bin/env bash

set -euo pipefail

conda_root="${1:-$HOME/anaconda3}"
conda_hook="$conda_root/etc/profile.d/conda.sh"

if [[ ! "$conda_root" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
    printf 'Conda root must be a simple absolute path: %s\n' "$conda_root" >&2
    exit 4
fi
if [[ ! -f "$conda_hook" ]]; then
    printf 'Conda shell hook not found: %s\n' "$conda_hook" >&2
    exit 5
fi

# shellcheck disable=SC1090
source "$conda_hook"
conda init bash
conda config --set auto_activate_base true

printf 'Conda Bash initialization is configured for this user.\n'
printf 'Reconnect SSH or run: source ~/.bashrc\n'
printf 'To disable automatic base activation later:\n'
printf '  conda config --set auto_activate_base false\n'
