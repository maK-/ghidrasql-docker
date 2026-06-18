#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

bash scripts/setup.sh

LOCAL_GHIDRA=""
if [[ "${1:-}" == "--local" ]]; then
  LOCAL_GHIDRA="${2:?Usage: $0 --local /path/to/ghidra_12.0.4_PUBLIC}"
  if [[ ! -f "$LOCAL_GHIDRA/support/analyzeHeadless" ]]; then
    echo "ERROR: Not a Ghidra distribution: $LOCAL_GHIDRA" >&2
    exit 1
  fi
fi

if [[ -n "$LOCAL_GHIDRA" ]]; then
  echo "Building ghidrasql-ai-base:latest from local tree: $LOCAL_GHIDRA"
  docker build -f Dockerfile.base.local \
    --build-context "ghidra=$LOCAL_GHIDRA" \
    -t ghidrasql-ai-base:latest .
else
  echo "Building ghidrasql-ai-base:latest (download Ghidra 12.0.4) ..."
  docker build -f Dockerfile.base -t ghidrasql-ai-base:latest .
fi

echo "Building ghidrasql-ai:latest ..."
docker build -f Dockerfile -t ghidrasql-ai:latest .

echo "Done. Images: ghidrasql-ai-base:latest, ghidrasql-ai:latest"
echo "Next: ./scripts/import-demo.sh  (or docker compose up -d after import)"
