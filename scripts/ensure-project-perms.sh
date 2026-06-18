#!/usr/bin/env bash
# Ensure ./projects is writable by Ghidra in the container (uid 1001).
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p projects

GHIDRA_UID=1001
GHIDRA_GID=1001

owner_uid="$(stat -c '%u' projects 2>/dev/null || stat -f '%u' projects 2>/dev/null || echo unknown)"

if [[ "$owner_uid" == "$GHIDRA_UID" ]] && [[ -w projects ]]; then
    exit 0
fi

echo "projects/ must be owned by uid $GHIDRA_UID (ghidra user in container); currently uid $owner_uid"

if [[ "$(id -u)" -eq 0 ]]; then
    chown -R "$GHIDRA_UID:$GHIDRA_GID" projects
    echo "Fixed: chown -R $GHIDRA_UID:$GHIDRA_GID projects"
    exit 0
fi

echo "ERROR: run as root or fix manually:" >&2
echo "  sudo chown -R $GHIDRA_UID:$GHIDRA_GID projects" >&2
exit 1
