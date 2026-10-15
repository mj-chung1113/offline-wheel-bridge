#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/pack-environment.sh"
"$SCRIPT_DIR/sync-environment.sh"
