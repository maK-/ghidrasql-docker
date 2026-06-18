# ghidrasql-ai

In a world where large corporations can simply steal all your code or data to train AI and sell it back to you, it's time hacking and hackers regained their political conscience. Hackers have grown politically inept in the pursuit of profit while our tools have grown better. This is a docker build of Elias's wonderful projects [ghidrasql](https://github.com/0xeb/ghidrasql/) and [libghidra](https://github.com/0xeb/libghidra). Reverse engineering is hard and slow to do, any effort to make it that little bit easier should be celebrated. Leverage the tools of oppression and surveillance against your adversary (big tech) - in this case use AI against them. All information deserves to be free so set your AI minions on their proprietary software and hack the planet. They can run but they can't hide from the ghidra.

Docker release for running [ghidrasql](https://github.com/0xeb/ghidrasql) over a live [LibGhidraHost](https://github.com/0xeb/libghidra) / Ghidra stack.

Two long-running containers expose:

- **LibGhidraHost RPC** at `http://127.0.0.1:18080`
- **SQL HTTP API** at `http://127.0.0.1:8081/query`

## Prerequisites

- Docker and Docker Compose
- ~8 GB RAM allocated to Docker (build and analysis are memory-heavy)
- ~4 GB free disk for image build
- On Windows: [Docker Desktop](https://www.docker.com/products/docker-desktop/) with WSL2 backend (recommended)

## Pinned versions

| Component | Version / ref |
|-----------|---------------|
| Ghidra | **12.0.4** PUBLIC (20260303) — validated in original `ghidra-ai` stack |
| libghidra | `main` |
| libxsql | `ea11622eeec5ac7e5988364ebfaffefccb1bb3f4` |
| ghidrasql | `main` |
| ghidrasql-skills | `main` |

Ghidra **12.0.4** matches the working dev image (`ghidra-base:local`). libghidra requires 12.0.4+; ghidrasql upstream docs mention 12.1+ but this release was validated on 12.0.4. See [docs/BUILD.md](docs/BUILD.md) for version notes and the historical `MemoryBlock` patch errors.

## Quick start

### 1. Build images

Linux / macOS / Git Bash: This does everything needed before running `docker compose up -d`

```bash
./build.sh
```

Windows (cmd or PowerShell):

```bat
build.bat
```

This builds `ghidrasql-ai-base:latest` (Ghidra 12.0.4), `ghidrasql-ai:latest`, and compiles `samples/hello` when `gcc` is available.

Use a local extracted Ghidra tree instead of downloading:

```bash
./build.sh --local ../ghidra_12.0.4_PUBLIC
```

```bat
build.bat --local ..\ghidra_12.0.4_PUBLIC
```

### 2. Import a demo binary

Compile the sample (Linux/macOS):

```bash
gcc -o samples/hello samples/hello.c
```

Windows (MSVC):

```bat
cl samples\hello.c /Fe:samples\hello.exe
copy samples\hello.exe samples\hello
```

Or with MinGW:

```bat
gcc -o samples\hello samples\hello.c
```

Import and start (Linux/macOS):

```bash
cp .env.example .env
./scripts/import-demo.sh
# or manually: docker compose down && docker compose --profile import run --rm ghidrasql-import && docker compose up -d
```

If compose fails with `dependency ghidrasql-libghidra failed to start`, run `./scripts/diagnose.sh`.

Windows:

```bat
scripts\win\import-demo.bat
```

### 3. Smoke test

```bash
curl -sS -X POST http://127.0.0.1:8081/query \
  --data "SELECT COUNT(*) AS funcs FROM funcs"
```

Windows:

```bat
scripts\win\smoke-test.bat
```

## Daily operations

Start services:

```bash
cp .env.example .env   # first time only
docker compose up -d
```

Stop services:

```bash
docker compose down
```

Configure the active Ghidra project/program in `.env`:

```dotenv
GHIDRA_PROJECT_NAME=hello_demo
GHIDRA_PROGRAM_NAME=hello
```

## Documentation

| Doc | Purpose |
|-----|---------|
| [docs/BUILD.md](docs/BUILD.md) | Build troubleshooting — version choice, common errors |
| [docs/OPERATIONS.md](docs/OPERATIONS.md) | Quick reference — import, SQL examples, troubleshooting |
| [docs/ghidrasql_operational_guide_v1.md](docs/ghidrasql_operational_guide_v1.md) | Full operational guide — schema details, workflows, diagnostics |
| [docs/AI.md](docs/AI.md) | **Using with AI agents** — Cursor, Claude Code, ghidrasql-skills, SQL contract |

## Using with AI

This stack exposes a **SQL HTTP API** that coding agents query instead of opening Ghidra directly:

```bash
curl -sS -X POST http://127.0.0.1:8081/query \
  --data "SELECT name, printf('0x%X', address) AS addr FROM funcs LIMIT 10"
```

Install [ghidrasql-skills](https://github.com/0xeb/ghidrasql-skills) into your agent (bundled in the image at `/opt/ghidrasql-skills`) and follow [docs/AI.md](docs/AI.md) for Cursor, Claude Code, and Codex setup.

See [docs/OPERATIONS.md](docs/OPERATIONS.md) for day-to-day Docker operations.

## Windows scripts

| Script | Purpose |
|--------|---------|
| `build.bat` | Build both Docker images |
| `scripts\win\up.bat` | Create `.env` if missing; start services |
| `scripts\win\down.bat` | Stop services |
| `scripts\win\import-demo.bat` | Import `samples\hello` and start services |
| `scripts\win\smoke-test.bat` | Run a baseline SQL query |

## Architecture

```text
ghidrasql-libghidra   Ghidra headless + LibGhidraHost  :18080
ghidrasql-server      ghidrasql SQL proxy              :8081
```

`ghidrasql-server` connects to `ghidrasql-libghidra` by URL and does not open the Ghidra project itself.

## Native Windows (without Docker)

This repository packages the **Docker** workflow only. For a native Windows install (Ghidra zip + VS 2022 + CMake + Gradle), follow the upstream runbooks:

- [ghidrasql install-prompt.md](https://github.com/0xeb/ghidrasql/blob/main/install-prompt.md)
- [libghidra README](https://github.com/0xeb/libghidra)

## License

Components retain their upstream licenses (Ghidra: Apache 2.0; ghidrasql/libghidra: MPL 2.0).
