# ghidrasql Operations Guide

Quick operational reference for the `ghidrasql-ai` Docker deployment.

**Full guide:** [ghidrasql_operational_guide_v1.md](ghidrasql_operational_guide_v1.md) — complete schema reference, SQL workflows, diagnostics, and AI skill map.

**AI agents:** [AI.md](AI.md) — connect Cursor/Claude/Codex to the SQL endpoint and install ghidrasql-skills.

## Service topology

```text
Ghidra project
  └─ ProgramDB
       └─ LibGhidraHost (ghidrasql-libghidra container, :18080)
            └─ ghidrasql (ghidrasql-server container, :8081/query)
```

| Service | Port | Role |
|---------|------|------|
| `ghidrasql-libghidra` | 18080 | Owns project lock; runs LibGhidraHost headless server |
| `ghidrasql-server` | 8081 | SQL HTTP endpoint; connects via `--url` |

Only one Ghidra process should own a project at a time.

## Configuration

Copy `.env.example` to `.env`:

```dotenv
GHIDRA_PROJECT_NAME=hello_demo
GHIDRA_PROGRAM_NAME=hello
GHIDRA_IMPORT_FILE=hello
GHIDRA_ANALYSIS_TIMEOUT=300
```

Start / stop:

```bash
docker compose up -d
docker compose down
docker compose logs -f ghidrasql-libghidra
docker compose logs -f ghidrasql-server
```

## Import a binary

Ghidra projects are lock-protected. Stop running services before importing.

### One-shot import (recommended)

```bash
docker compose down

# Put binary at samples/your_binary (no extension is fine)
docker compose --profile import run --rm ghidrasql-import

# Or with explicit env:
GHIDRA_PROJECT_NAME=adhoc_demo GHIDRA_IMPORT_FILE=target1 \
  docker compose --profile import run --rm ghidrasql-import

# Update .env with project/program names, then:
docker compose up -d
```

### Manual import

```bash
docker compose down

docker run --rm \
  -e MODE=headless \
  -v "$PWD/samples:/samples:ro" \
  -v "$PWD/projects:/projects" \
  ghidrasql-ai:latest \
  /projects adhoc_demo \
  -import /samples/target1 \
  -overwrite \
  -analysisTimeoutPerFile 300
```

### Multiple binaries in one project

Import each binary with separate one-shot runs (same `GHIDRA_PROJECT_NAME`, different import paths). Switch the active program by changing `GHIDRA_PROGRAM_NAME` in `.env` and restarting:

```bash
docker compose down
docker compose up -d
```

### Find the correct program name

If `-process hello` fails, list project programs:

```bash
curl -sS -X POST http://127.0.0.1:8081/query \
  --data "SELECT path, name FROM project_programs ORDER BY path"
```

Use the path/name shown (often `/hello` or the imported filename).

## Health checks

SQL server:

```bash
curl -sS -X POST http://127.0.0.1:8081/query \
  --data "SELECT COUNT(*) AS memory_blocks FROM memory_blocks"
```

Baseline validation:

```bash
curl -sS -X POST http://127.0.0.1:8081/query \
  --data "SELECT
        (SELECT COUNT(*) FROM memory_blocks) AS memory_blocks,
        (SELECT COUNT(*) FROM funcs) AS funcs,
        (SELECT COUNT(*) FROM instructions) AS instructions,
        (SELECT COUNT(*) FROM names) AS names,
        (SELECT COUNT(*) FROM xrefs) AS xrefs,
        (SELECT COUNT(*) FROM callgraph_edges) AS callgraph_edges,
        (SELECT COUNT(*) FROM function_calls) AS function_calls,
        (SELECT COUNT(*) FROM pseudocode) AS pseudocode"
```

A healthy analyzed binary should show non-zero `memory_blocks`, `funcs`, `instructions`, and `names`.

## Introspection

Discover schema before querying:

```sql
SELECT type, name FROM sqlite_master ORDER BY type, name;
PRAGMA table_info(funcs);
PRAGMA table_info(memory_blocks);
PRAGMA table_info(names);
PRAGMA table_info(strings);
PRAGMA table_info(xrefs);
```

## Common SQL

### Functions

```sql
SELECT printf('0x%X', address) AS addr, name, size, signature
FROM funcs
ORDER BY address
LIMIT 20;
```

### Instructions in a range

```sql
SELECT printf('0x%X', address) AS addr, mnemonic, operands
FROM instructions
WHERE address BETWEEN 0x401165 AND 0x4011B5
ORDER BY address;
```

### Pseudocode

```sql
SELECT text FROM pseudocode WHERE func_addr = 0x401165;
```

### Xrefs

```sql
SELECT printf('0x%X', from_ea) AS from_ea,
       printf('0x%X', to_ea) AS to_ea,
       kind, is_code, is_data
FROM xrefs
ORDER BY from_ea, to_ea
LIMIT 50;
```

### Call graph

```sql
SELECT printf('0x%X', src_func_addr) AS src,
       src_func_name,
       printf('0x%X', dst_func_addr) AS dst,
       dst_func_name
FROM callgraph_edges
LIMIT 50;
```

### Memory blocks

```sql
SELECT printf('0x%X', start_ea) AS start_addr,
       printf('0x%X', end_ea) AS end_addr,
       name, class, is_exec, size
FROM memory_blocks
ORDER BY start_ea;
```

Use column `class` (not `block_class`). Avoid alias `AS end` (reserved).

### Strings

```sql
SELECT printf('0x%X', address) AS addr, length, content
FROM strings
LIMIT 20;
```

Use `content`, not `value`.

## SQL quoting

Use single quotes for string literals:

```sql
printf('0x%X', address)
```

Double quotes may be treated as identifier quoting and cause `success:false`.

## Write operations

```sql
UPDATE funcs SET name = 'my_main' WHERE address = 0x401000;
SELECT save_database();
```

For decompiler locals, query `local_id` first and reuse the exact value in updates.

## Troubleshooting

### `ghidrasql-libghidra` failed / dependency failed to start

Compose waits for `ghidrasql-libghidra` health on `http://127.0.0.1:18080/health`. If that never passes, `ghidrasql-server` shows:

```text
dependency ghidrasql-libghidra failed to start
```

**Most common cause:** no imported project yet. Compose uses `-process hello` on project `hello_demo`, but `projects/` is empty until you import.

On your Linux server, from the repo root:

```bash
chmod +x scripts/diagnose.sh scripts/import-demo.sh
./scripts/diagnose.sh
```

**First-time setup (import then start):**

```bash
cp .env.example .env
gcc -o samples/hello samples/hello.c
docker compose down
docker compose --profile import run --rm ghidrasql-import
docker compose up -d
docker compose logs -f ghidrasql-libghidra
```

Or one shot: `./scripts/import-demo.sh`

**See the real startup error** (foreground, no healthcheck timeout):

```bash
docker compose down
docker run --rm -it \
  -e MODE=headless \
  -p 127.0.0.1:18080:18080 \
  -v "$PWD/projects:/projects" \
  ghidrasql-ai:latest \
  /projects hello_demo \
  -process hello \
  -scriptPath /opt/ghidrasql/scripts \
  -postScript LibGhidraHeadlessServer.java \
  bind=0.0.0.0 port=18080 shutdown=none max_runtime_ms=0
```

Other causes: stale `*.lock` files, port 18080 in use, wrong `GHIDRA_PROGRAM_NAME` after import (list programs with SQL after partial start), permissions on `./projects` (container user uid 1001).

### Project lock errors

```text
LockException: Unable to lock project!
```

Only one Ghidra process may open a project. Stop all containers first:

```bash
docker compose down
docker stop ghidrasql-server ghidrasql-libghidra 2>/dev/null || true
```

Remove stale locks only after processes are stopped:

```bash
find ./projects -name '*.lock' -o -name '*.lock~' -print -delete
```

### Port conflicts

```bash
# Linux/macOS
ss -ltnp | grep -E ':18080|:8081'
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

Ports:

- `18080` — LibGhidraHost RPC
- `8081` — ghidrasql SQL HTTP

### Empty funcs / instructions / xrefs

Confirm analysis completed during import. Re-import with a longer timeout:

```dotenv
GHIDRA_ANALYSIS_TIMEOUT=600
```

Validate LibGhidraHost directly:

```bash
curl -sS http://127.0.0.1:18080/health
```

### `success:false` with empty error

Common causes: wrong column name, reserved alias (`END`), double-quoted string literals, schema mismatch. Use `PRAGMA table_info(table_name)` and `SELECT * FROM table_name LIMIT 1`.

## Operational checklist

**Import a new binary**

1. Copy binary into `./samples`
2. `docker compose down`
3. Run import (profile or manual)
4. Set `GHIDRA_PROJECT_NAME` and `GHIDRA_PROGRAM_NAME` in `.env`
5. `docker compose up -d`
6. Run baseline validation query

**Switch active program**

1. `docker compose down`
2. Change `GHIDRA_PROGRAM_NAME` in `.env`
3. `docker compose up -d`
4. Validate with funcs count query

**Save mutations**

```sql
SELECT save_database();
```

## Further reading

- [ghidrasql_operational_guide_v1.md](ghidrasql_operational_guide_v1.md) — full operational guide (schema, workflows, skill map)
- [AI.md](AI.md) — using this stack with AI coding agents
