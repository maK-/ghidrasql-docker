#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/setup.sh
if ! ./scripts/ensure-project-perms.sh; then
    echo "ERROR: fix projects/ permissions before import (see above)" >&2
    exit 1
fi

echo "Stopping services ..."
docker compose down

echo "Importing samples/hello into project hello_demo ..."
docker compose --profile import run --rm ghidrasql-import

echo "Starting services ..."
docker compose up -d

echo "Waiting for health ..."
sleep 5
curl -fsS http://127.0.0.1:18080/health && echo " LibGhidraHost OK" || echo " LibGhidraHost not ready yet"
curl -fsS -X POST http://127.0.0.1:8081/query --data "SELECT COUNT(*) AS funcs FROM funcs" || echo " SQL not ready yet (check: docker compose logs -f)"

echo "Done. SQL: http://127.0.0.1:8081/query"
