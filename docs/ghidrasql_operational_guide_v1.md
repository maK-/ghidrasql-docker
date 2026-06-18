# ghidrasql Operational Guide v1

Model-neutral documentation for using ghidrasql, LibGhidraHost, and Ghidra as a live reverse-engineering query stack.

This guide describes the runtime model, service topology, ad-hoc binary loading, safe connection patterns, schema realities, useful SQL workflows, performance behavior, diagnostics, and the implementation discoveries made while validating ghidrasql against the **ghidrasql-ai** containerized Ghidra setup.

For AI-agent setup (Cursor, Claude Code, Codex, and similar), see [AI.md](AI.md).

---

## 0. Using with AI agents

This stack is designed for **model-neutral** reverse-engineering workflows: an AI agent sends SQL to a live Ghidra program and reads structured JSON back.

### 0.1 What the agent talks to

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `POST http://127.0.0.1:8081/query` | Raw SQL body (`text/plain`) | Primary agent interface — functions, xrefs, pseudocode, mutations |
| `http://127.0.0.1:18080` | LibGhidra protobuf RPC | Lower-level; prefer SQL unless you need RPC-specific operations |

Start the stack from this repo:

```bash
docker compose up -d
```

Smoke test:

```bash
curl -sS -X POST http://127.0.0.1:8081/query \
  --data "SELECT COUNT(*) AS funcs FROM funcs"
```

### 0.2 ghidrasql-skills

The Docker image includes [ghidrasql-skills](https://github.com/0xeb/ghidrasql-skills) at `/opt/ghidrasql-skills`. These are focused skill modules (`connect`, `analysis`, `disassembly`, `xrefs`, `decompiler`, `annotations`, `types`, …) that teach agents how to query and annotate binaries safely.

Install skills for your agent (see [AI.md](AI.md) for Cursor-specific steps):

- **Claude Code:** `/plugin marketplace add 0xeb/ghidrasql-skills`
- **Codex:** install from `plugins/ghidrasql/.codex-plugin/plugin.json` in that repo
- **Cursor:** copy or symlink skill folders from `/opt/ghidrasql-skills` (or clone the repo) into your agent skills path

Skill map (section 16 below) lists each module's purpose.

### 0.3 Agent workflow (recommended)

```text
1. Ensure ghidrasql-ai services are up and the target binary is imported.
2. Run baseline validation (section 15).
3. Introspect schema: sqlite_master, PRAGMA table_info(...).
4. Use narrow, bounded queries (LIMIT, address ranges) before wide scans.
5. For writes: read → update → SELECT save_database() → re-read.
6. Prefer single-quoted SQL string literals; avoid alias END.
```

Point the agent at this guide plus [AI.md](AI.md) when starting a RE session. The agent does not need Ghidra GUI access — only the SQL HTTP endpoint on port 8081.

---

## 1. Purpose

`ghidrasql` provides a SQL interface over a live Ghidra program. It is useful when you want repeatable, scriptable access to:

- functions
- instructions
- memory blocks
- symbols and names
- xrefs
- call graphs
- pseudocode
- strings
- comments
- annotations and write operations

It is best treated as a SQL façade over a single active Ghidra program. A Ghidra project may contain multiple programs, but a given LibGhidraHost/ghidrasql session should be considered bound to one active program at a time.

---

## 2. Components

A working deployment has these layers:

```text
Ghidra project
  └─ ProgramDB
       └─ LibGhidraHost extension
            └─ HTTP/protobuf RPC endpoint, usually 127.0.0.1:18080
                 └─ ghidrasql
                      └─ SQL CLI, REPL, or SQL HTTP endpoint, usually 127.0.0.1:8081/query
```

### 2.1 LibGhidraHost

LibGhidraHost owns the active Ghidra program session and exposes program operations through HTTP/protobuf RPC.

Typical endpoint:

```text
http://127.0.0.1:18080
```

This port does **not** speak SQL.

### 2.2 ghidrasql

ghidrasql connects to a LibGhidraHost source and exposes SQL tables, views, helper functions, and mutation operations.

Typical SQL endpoint:

```text
POST http://127.0.0.1:8081/query
```

Example:

```bash
curl -sS -X POST http://127.0.0.1:8081/query \
  --data "SELECT name, printf('0x%X', address) AS addr FROM funcs ORDER BY address LIMIT 10" | jq
```

---

## 3. Recommended Docker Compose topology

Use two long-running services:

```text
ghidrasql-libghidra  owns the Ghidra project lock and exposes LibGhidraHost
ghidrasql-server     connects to ghidrasql-libghidra by --url and exposes SQL
```

`ghidrasql-server` should not open the project itself when `ghidrasql-libghidra` already owns it.

### 3.1 Compose pattern

```yaml
services:
  ghidrasql-libghidra:
    image: ghidrasql-ai:latest
    container_name: ghidrasql-libghidra
    environment:
      MODE: headless
    ports:
      - "127.0.0.1:18080:18080"
    volumes:
      - ./projects:/projects
    command:
      - /projects
      - ${GHIDRA_PROJECT_NAME:-hello_demo}
      - -process
      - ${GHIDRA_PROGRAM_NAME:-hello}
      - -scriptPath
      - /opt/ghidrasql/scripts
      - -postScript
      - LibGhidraHeadlessServer.java
      - bind=0.0.0.0
      - port=18080
      - shutdown=none
      - max_runtime_ms=0

  ghidrasql-server:
    image: ghidrasql-ai:latest
    container_name: ghidrasql-server
    depends_on:
      - ghidrasql-libghidra
    environment:
      MODE: ghidrasql
    ports:
      - "127.0.0.1:8081:8081"
    command:
      - --url
      - http://ghidrasql-libghidra:18080
      - --http
      - --bind
      - 0.0.0.0
      - --port
      - "8081"
```

### 3.2 `.env` example

```dotenv
GHIDRA_PROJECT_NAME=hello_demo
GHIDRA_PROGRAM_NAME=hello
```

Start:

```bash
docker compose up -d
```

Stop:

```bash
docker compose down
```

Logs:

```bash
docker compose logs -f ghidrasql-libghidra
docker compose logs -f ghidrasql-server
```

---

## 4. Loading binaries ad hoc

### 4.1 Best mechanism: one-shot importer container

The most reliable ad-hoc loading workflow is:

```text
1. Put binary in ./samples or ./binaries.
2. Stop long-running services so the project is not locked.
3. Run a one-shot analyzeHeadless import container.
4. Restart ghidrasql-libghidra and ghidrasql-server against the imported program.
```

This is preferred because Ghidra projects are lock-protected. Importing or analyzing through a second Ghidra process while LibGhidraHost has the project open will cause lock errors.

### 4.2 Directory layout

Recommended project layout:

```text
ghidrasql-ai-build/
  docker-compose.yml
  .env
  projects/
  samples/
    hello
    target1
    target2
```

### 4.3 Import command

Example import of `samples/target1` into project `adhoc_demo`:

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

Then set:

```dotenv
GHIDRA_PROJECT_NAME=adhoc_demo
GHIDRA_PROGRAM_NAME=target1
```

Restart:

```bash
docker compose up -d
```

Validate:

```bash
curl -sS -X POST http://127.0.0.1:8081/query \
  --data "SELECT COUNT(*) AS funcs FROM funcs" | jq
```

### 4.4 Compose profile for importing

You can also add an importer service to Compose. It should be run manually and should not run at the same time as the long-running services.

```yaml
  ghidrasql-import:
    image: ghidrasql-ai:latest
    profiles: ["import"]
    environment:
      MODE: headless
    volumes:
      - ./projects:/projects
      - ./samples:/samples:ro
    command:
      - /projects
      - ${GHIDRA_PROJECT_NAME:-adhoc_demo}
      - -import
      - /samples/${GHIDRA_IMPORT_FILE}
      - -overwrite
      - -analysisTimeoutPerFile
      - "${GHIDRA_ANALYSIS_TIMEOUT:-300}"
```

Run:

```bash
docker compose down

GHIDRA_PROJECT_NAME=adhoc_demo \
GHIDRA_IMPORT_FILE=target1 \
docker compose --profile import run --rm ghidrasql-import

GHIDRA_PROJECT_NAME=adhoc_demo GHIDRA_PROGRAM_NAME=target1 docker compose up -d
```

### 4.5 Importing multiple binaries into one project

You can import multiple binaries into one Ghidra project:

```bash
docker compose down

docker run --rm \
  -e MODE=headless \
  -v "$PWD/samples:/samples:ro" \
  -v "$PWD/projects:/projects" \
  ghidrasql-ai:latest \
  /projects malware_lab \
  -import /samples/sample_a \
  -overwrite \
  -analysisTimeoutPerFile 300

docker run --rm \
  -e MODE=headless \
  -v "$PWD/samples:/samples:ro" \
  -v "$PWD/projects:/projects" \
  ghidrasql-ai:latest \
  /projects malware_lab \
  -import /samples/sample_b \
  -overwrite \
  -analysisTimeoutPerFile 300
```

Select one active program by setting:

```dotenv
GHIDRA_PROJECT_NAME=malware_lab
GHIDRA_PROGRAM_NAME=sample_a
```

or:

```dotenv
GHIDRA_PROJECT_NAME=malware_lab
GHIDRA_PROGRAM_NAME=sample_b
```

Then restart:

```bash
docker compose up -d
```

### 4.6 Program path versus display name

Ghidra stores imported files as project paths, often like:

```text
/hello
/target1
/folder/target2
```

If `-process target1` does not find the program, list project programs:

```bash
curl -sS -X POST http://127.0.0.1:8081/query \
  --data "SELECT path, name FROM project_programs ORDER BY path" | jq
```

Then use the correct program name/path in the LibGhidraHost startup command.

### 4.7 Can binaries be loaded without restarting?

There are three possible approaches, but restarting remains the safest.

#### Approach A: one-shot import plus restart

Recommended.

```text
Reliable
Reproducible
Avoids project locks
Simple to operate
```

#### Approach B: import into a separate project while current service stays up

Useful if you want the current SQL service uninterrupted.

```text
Project A remains live.
Project B is imported/analyzed by a one-shot job.
Later, restart services to point at Project B.
```

#### Approach C: runtime open/import through LibGhidra APIs

Possible only if the available LibGhidraHost APIs support the required open/import operations and ghidrasql cache invalidation is handled correctly.

Caveats:

```text
The active program may change under ghidrasql.
Cached tables may become stale.
Long-running decompiler/cache state may need invalidation.
Operational behavior is harder to reason about.
```

For production-style workflows, use Approach A or B.

---

## 5. Connection modes

### 5.1 Proxy mode

Use this when LibGhidraHost is already running:

```bash
ghidrasql \
  --url http://127.0.0.1:18080 \
  --http \
  --bind 127.0.0.1 \
  --port 8081
```

### 5.2 Managed mode

Use this only when no other Ghidra process owns the project:

```bash
ghidrasql \
  --ghidra /ghidra \
  --project /projects \
  --project-name hello_demo \
  --program hello \
  --no-analyze \
  --http \
  --bind 0.0.0.0 \
  --port 8081
```

### 5.3 Project lock rule

Only one Ghidra process should own a project at a time.

If a managed ghidrasql process and a manual LibGhidraHost both open the same project, startup can fail with:

```text
LockException: Unable to lock project!
```

---

## 6. Health checks

### 6.1 SQL server

```bash
curl -sS -X POST http://127.0.0.1:8081/query \
  --data "SELECT COUNT(*) AS memory_blocks FROM memory_blocks" | jq
```

### 6.2 Core surface validation

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
        (SELECT COUNT(*) FROM pseudocode) AS pseudocode" | jq
```

A healthy analyzed binary should usually produce non-zero values for:

```text
memory_blocks
funcs
instructions
names
```

For binaries with normal calls and references, also expect:

```text
xrefs
callgraph_edges
function_calls
```

---

## 7. Introspection first

Do not guess table schemas. Use:

```sql
SELECT type, name FROM sqlite_master ORDER BY type, name;
PRAGMA table_info(funcs);
PRAGMA table_info(memory_blocks);
PRAGMA table_info(names);
PRAGMA table_info(strings);
PRAGMA table_info(xrefs);
```

HTTP example:

```bash
curl -sS -X POST http://127.0.0.1:8081/query \
  --data "PRAGMA table_info(names)" | jq
```

---

## 8. Observed schema details

### 8.1 memory_blocks

Observed schema:

```text
start_ea
end_ea
name
class
perm
bitness
size
is_read
is_write
is_exec
```

Use `class`, not `block_class`.

Correct query:

```sql
SELECT printf('0x%X', start_ea) AS start_addr,
       printf('0x%X', end_ea) AS end_addr,
       name,
       class,
       is_read,
       is_write,
       is_exec,
       size
FROM memory_blocks
ORDER BY start_ea;
```

Avoid aliases such as `AS end`.

### 8.2 names

Observed schema:

```text
address
name
symbol_kind
namespace
is_primary
is_external
```

Use `symbol_kind` and `namespace`, not `symbol_type` or `namespace_name`.

Correct query:

```sql
SELECT printf('0x%X', address) AS addr,
       name,
       namespace,
       symbol_kind
FROM names
ORDER BY address
LIMIT 50;
```

### 8.3 strings

Observed schema:

```text
address
ea
length
type
type_name
width
width_name
layout
layout_name
encoding
content
```

Use `content`, not `value`.

Exact-address lookup:

```sql
SELECT printf('0x%X', address) AS addr,
       length,
       type_name,
       encoding,
       content
FROM strings
WHERE address = 0x402004;
```

### 8.4 xrefs

Observed schema:

```text
from_ea
to_ea
kind
is_code
is_data
```

Correct query:

```sql
SELECT printf('0x%X', from_ea) AS from_ea,
       printf('0x%X', to_ea) AS to_ea,
       kind,
       is_code,
       is_data
FROM xrefs
ORDER BY from_ea, to_ea
LIMIT 50;
```

---

## 9. SQL quoting rules

Use single quotes for string literals:

```sql
printf('0x%X', address)
```

Do not rely on double quotes for SQL string literals:

```sql
printf("0x%X", address)
```

Double quotes may be treated as identifier quoting and can produce confusing `success:false` results.

---

## 10. Practical SQL workflows

### 10.1 Functions

```sql
SELECT printf('0x%X', address) AS addr,
       name,
       size,
       signature
FROM funcs
ORDER BY address;
```

### 10.2 Instructions

```sql
SELECT printf('0x%X', address) AS addr,
       mnemonic,
       operands
FROM instructions
WHERE address BETWEEN 0x401165 AND 0x4011B5
ORDER BY address;
```

If `operands` is not present in your build, check:

```sql
PRAGMA table_info(instructions);
```

### 10.3 Pseudocode

Always filter by `func_addr` for decompiler-backed tables:

```sql
SELECT text
FROM pseudocode
WHERE func_addr = 0x401165;
```

By name:

```sql
SELECT p.text
FROM funcs f
JOIN pseudocode p ON p.func_addr = f.address
WHERE f.name = 'main';
```

### 10.4 Xrefs

```sql
SELECT printf('0x%X', from_ea) AS from_ea,
       printf('0x%X', to_ea) AS to_ea,
       kind,
       is_code,
       is_data
FROM xrefs
WHERE from_ea BETWEEN 0x401165 AND 0x4011B5
ORDER BY from_ea, to_ea;
```

### 10.5 Call graph

```sql
SELECT printf('0x%X', src_func_addr) AS src,
       src_func_name,
       printf('0x%X', dst_func_addr) AS dst,
       dst_func_name,
       printf('0x%X', call_site) AS site,
       kind
FROM callgraph_edges
ORDER BY src_func_addr, call_site;
```

### 10.6 Strings via xrefs

For string discovery, start from data references:

```sql
SELECT DISTINCT to_ea
FROM xrefs
WHERE to_ea BETWEEN 0x402000 AND 0x402100
ORDER BY to_ea;
```

Then probe exact addresses:

```sql
SELECT printf('0x%X', address) AS addr,
       length,
       type_name,
       encoding,
       content
FROM strings
WHERE address = 0x402004;
```

In the validated build, exact string lookup worked, while unbounded and ranged string scans did not materialize the same rows. Treat exact-address string lookup as the reliable path unless `read_strings()` has been patched to scan memory blocks.

---

## 11. Live-source all-address RPC issue

During validation, several libghidra-backed ghidrasql surfaces returned zero rows when the source implementation called list APIs over the full address space:

```cpp
ListFunctions(0, UINT64_MAX, ...)
ListInstructions(0, UINT64_MAX, ...)
ListSymbols(0, UINT64_MAX, ...)
ListXrefs(0, UINT64_MAX, ...)
```

The same APIs worked when called over real memory block ranges.

### 11.1 Symptom

```text
memory_blocks > 0
funcs = 0
instructions = 0
names = 0
xrefs = 0
```

### 11.2 Reliable implementation pattern

```text
ListMemoryBlocks()
for each relevant block:
    call the live list API over block.start_address..block.end_address
deduplicate rows
sort by address
```

Executable blocks are appropriate for:

```text
functions
instructions
basic blocks
CFG
```

All readable/mapped blocks are appropriate for:

```text
symbols / names
xrefs
strings
comments
data items
```

### 11.3 Patches validated locally

The following methods were patched successfully:

```text
read_functions()
read_instructions()
read_symbols()
read_xrefs()
```

After patching, the test ELF produced:

```text
memory_blocks    39
funcs            13
instructions     111
names            42
xrefs            103
callgraph_edges  9
function_calls   9
pseudocode        13
```

---

## 12. Mutation workflow

For writes, use an explicit read-write-save-verify loop:

```text
read exact target
write exact target
save
re-read target
```

Rename/signature example:

```sql
SELECT name, signature
FROM funcs
WHERE address = 0x401165;

UPDATE funcs
SET name = 'main',
    signature = 'int main(void)'
WHERE address = 0x401165;

SELECT save_database();

SELECT name, signature
FROM funcs
WHERE address = 0x401165;
```

---

## 13. Troubleshooting

### 13.1 Container starts then disappears

Run foreground to see the real error:

```bash
docker run --rm --name ghidrasql-server ...same arguments...
```

### 13.2 Unable to lock project

Cause: another Ghidra/LibGhidraHost process owns the project.

Fix:

```bash
docker compose down
docker stop ghidrasql-server 2>/dev/null || true
docker stop ghidrasql-libghidra 2>/dev/null || true
```

Only delete lock files after the owning process is stopped:

```bash
find "$PWD/projects" \( -name '*.lock' -o -name '*.lock~' \) -print -delete
```

### 13.3 Port conflicts

```bash
sudo ss -ltnp | grep -E ':18080|:8081'
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Command}}'
```

Typical ports:

```text
18080  LibGhidraHost RPC
8081   ghidrasql SQL HTTP
```

### 13.4 `success:false` with empty error

Common causes:

```text
wrong column name
reserved alias such as END
double-quoted string literal
schema mismatch between docs and build
```

Use:

```sql
PRAGMA table_info(table_name);
SELECT * FROM table_name LIMIT 1;
```

---

## 14. Operational checklist

### 14.1 Import a new binary

```text
1. Copy binary into ./samples.
2. docker compose down.
3. Run one-shot analyzeHeadless import.
4. Set GHIDRA_PROJECT_NAME and GHIDRA_PROGRAM_NAME.
5. docker compose up -d.
6. Run baseline validation query.
```

### 14.2 Start an existing analyzed program

```text
1. Set GHIDRA_PROJECT_NAME.
2. Set GHIDRA_PROGRAM_NAME.
3. docker compose up -d.
4. Confirm funcs/instructions/names/xrefs counts.
```

### 14.3 Switch active program

```text
1. docker compose down.
2. Change GHIDRA_PROGRAM_NAME.
3. docker compose up -d.
4. Validate active program with funcs and db_info/project_programs.
```

### 14.4 Save mutations

```sql
SELECT save_database();
```

---

## 15. Baseline validation query

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
        (SELECT COUNT(*) FROM pseudocode) AS pseudocode" | jq
```

---

## 16. Skill map (ghidrasql-skills)

These modules ship in [ghidrasql-skills](https://github.com/0xeb/ghidrasql-skills) and are baked into the `ghidrasql-ai` image at `/opt/ghidrasql-skills`. Install them into your AI agent so it follows consistent query and annotation patterns. See [AI.md](AI.md).

| Module | Purpose |
|---|---|
| connect | Session bootstrap, endpoints, lifecycle, routing |
| analysis | High-level triage and summary queries |
| disassembly | Functions, instructions, blocks, CFG, loops, switches, raw code shape |
| xrefs | References, callers, callees, call graphs, string-reference tracing |
| data | Strings, memory blocks, bytes, data items, relocations, hexdumps |
| grep | Pattern matching across functions, names, imports, exports, types, strings |
| decompiler | Pseudocode, locals, parameters, tokens, decompiler-derived views |
| annotations | Persistent renames, comments, signatures, tags, saves |
| types | Structs, enums, unions, typedefs, signatures, type application |
| debugger | Breakpoints and patch-oriented workflows where supported |
| re-source | Bottom-up source recovery workflow over functions and call graph |
| functions | SQL helper function catalog |

---

## 17. Recommended documentation corrections

Prefer these schema names in examples:

```text
memory_blocks.class      not memory_blocks.block_class
names.namespace          not names.namespace_name
names.symbol_kind        not names.symbol_type
strings.content          not strings.value
```

Document that some live-source builds may require memory-block-ranged implementations instead of all-address list calls.

---

## 18. References reviewed

- Public repository: https://github.com/0xeb/ghidrasql-skills
- ghidrasql skill modules under: `plugins/ghidrasql/skills/` (also at `/opt/ghidrasql-skills` in the Docker image)
- Local validation against a Ghidra-analyzed ELF hello binary using LibGhidraHost, ghidrasql HTTP mode, and patched live-source range scans in the `ghidrasql-ai` image.
