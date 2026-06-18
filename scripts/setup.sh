#!/usr/bin/env bash
# Host-side project setup: script permissions, dirs, env, sample binary.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Setting up project ..."

for script in build.sh entrypoint.sh scripts/*.sh; do
    if [[ -f "$script" ]]; then
        chmod +x "$script"
    fi
done

if [[ ! -f .env ]] && [[ -f .env.example ]]; then
    cp .env.example .env
    echo "Created .env from .env.example"
fi

mkdir -p projects
if ! ./scripts/ensure-project-perms.sh; then
    echo "WARNING: projects/ may not be writable in the container; before import run:" >&2
    echo "  sudo chown -R 1001:1001 projects" >&2
fi

if [[ -f samples/hello.c ]]; then
    if command -v gcc >/dev/null 2>&1; then
        if [[ ! -f samples/hello ]] || [[ samples/hello.c -nt samples/hello ]]; then
            echo "Compiling samples/hello ..."
            gcc -o samples/hello samples/hello.c
        fi
    elif [[ ! -f samples/hello ]]; then
        echo "WARNING: gcc not found; samples/hello not built (install gcc or run: gcc -o samples/hello samples/hello.c)" >&2
    fi
fi

echo "Project setup complete."
