#!/bin/bash
set -euo pipefail

MODE="${MODE:-ghidrasql}"

if [[ "$MODE" == "ghidrasql" ]]; then
    exec /usr/local/bin/ghidrasql "$@"
fi

exec /ghidra/docker/entrypoint.sh "$@"
