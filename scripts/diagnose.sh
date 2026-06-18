#!/usr/bin/env bash
# Quick diagnostics for ghidrasql-ai on Linux. Run from repo root:
#   ./scripts/diagnose.sh
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== ghidrasql-ai diagnose ==="
echo "Working directory: $(pwd)"
echo

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found"
    exit 1
fi

echo "--- Images ---"
docker images ghidrasql-ai ghidrasql-ai-base --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' 2>/dev/null || true
echo

echo "--- Containers ---"
docker ps -a --filter 'name=ghidrasql' --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
echo

echo "--- .env ---"
if [[ -f .env ]]; then
    grep -E '^GHIDRA_' .env || true
else
    echo "WARNING: no .env (copy .env.example)"
fi
echo

echo "--- projects/ ---"
ls -la projects/ 2>/dev/null | head -10 || true
if [[ -d projects/hello_demo.rep ]] || ls projects/*.rep 2>/dev/null; then
    echo "Project present."
else
    echo "WARNING: no Ghidra project found under projects/"
    echo "  Import: ./scripts/import-demo.sh"
fi
proj_uid="$(stat -c '%u' projects 2>/dev/null || echo '?')"
if [[ "$proj_uid" != "1001" ]]; then
    echo "WARNING: projects/ owned by uid $proj_uid; container needs uid 1001"
    echo "  Fix: sudo chown -R 1001:1001 projects"
fi
echo

echo "--- samples/hello ---"
if [[ -f samples/hello ]]; then
    file samples/hello
else
    echo "WARNING: samples/hello missing (compile: gcc -o samples/hello samples/hello.c)"
fi
echo

echo "--- ghidrasql-libghidra logs (last 40 lines) ---"
docker logs ghidrasql-libghidra 2>&1 | tail -40 || echo "(container not running or no logs)"
echo

echo "--- Health ---"
curl -fsS --max-time 3 http://127.0.0.1:18080/health && echo " LibGhidraHost :18080 OK" || echo " LibGhidraHost :18080 FAILED"
curl -fsS --max-time 3 http://127.0.0.1:8081/health && echo " ghidrasql       :8081 OK" || echo " ghidrasql       :8081 FAILED"
echo

echo "--- Common fixes ---"
echo "1. Import:  ./scripts/import-demo.sh"
echo "2. Foreground libghidra (see real error):"
echo "   docker compose down"
echo "   docker run --rm -it -e MODE=headless -p 127.0.0.1:18080:18080 \\"
echo "     -v \"\$PWD/projects:/projects\" ghidrasql-ai:latest \\"
echo "     /projects hello_demo -process hello -scriptPath /opt/ghidrasql/scripts \\"
echo "     -postScript LibGhidraHeadlessServer.java bind=0.0.0.0 port=18080 shutdown=none max_runtime_ms=0"
