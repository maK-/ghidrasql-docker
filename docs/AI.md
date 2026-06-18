# Using ghidrasql-ai with AI agents

How to connect Cursor, Claude Code, Codex, or other coding agents to a live Ghidra program through SQL.

## Overview

```text
Your AI agent
  └─ POST http://127.0.0.1:8081/query  (raw SQL, text/plain)
       └─ ghidrasql-server container
            └─ LibGhidraHost @ :18080
                 └─ Ghidra ProgramDB (analyzed binary)
```

The agent never opens Ghidra directly. It sends SQL and receives JSON results — the same contract documented in [ghidrasql_operational_guide_v1.md](ghidrasql_operational_guide_v1.md).

## 1. Start the stack

From the repo root:

```bash
docker compose up -d
```

Or on Windows: `scripts\win\up.bat`

Confirm services are healthy:

```bash
curl -sS http://127.0.0.1:18080/health
curl -sS -X POST http://127.0.0.1:8081/query --data "SELECT COUNT(*) AS n FROM funcs"
```

Import a binary first if needed — see [OPERATIONS.md](OPERATIONS.md) or section 4 of the [full operational guide](ghidrasql_operational_guide_v1.md).

## 2. Install ghidrasql-skills

[ghidrasql-skills](https://github.com/0xeb/ghidrasql-skills) teaches agents *how* to query: schema introspection, xref tracing, decompiler workflows, safe mutations, and save semantics. Without skills, agents often guess column names or skip `save_database()`.

The skills are cloned into the Docker image at `/opt/ghidrasql-skills`. Copy them to your host for agent use:

```bash
docker run --rm ghidrasql-ai:latest cat /dev/null 2>/dev/null || true
docker create --name gs-skills ghidrasql-ai:latest
docker cp gs-skills:/opt/ghidrasql-skills ./ghidrasql-skills
docker rm gs-skills
```

Or clone directly:

```bash
git clone https://github.com/0xeb/ghidrasql-skills.git
```

### Cursor

1. Copy skill folders from `ghidrasql-skills/plugins/ghidrasql/skills/` (or the repo's skill tree) into your Cursor skills directory, **or** add the repo path when configuring agent skills.
2. Create a **Cursor rule** (`.cursor/rules/ghidrasql.mdc`) or project instruction that tells the agent:
   - SQL endpoint: `POST http://127.0.0.1:8081/query`
   - Request body: raw SQL, `Content-Type: text/plain`
   - Always introspect schema before wide queries
   - Call `SELECT save_database()` after mutations
3. Attach [ghidrasql_operational_guide_v1.md](ghidrasql_operational_guide_v1.md) as context for complex RE tasks.

Example rule snippet:

```markdown
When analyzing binaries in this project:
- Query via POST http://127.0.0.1:8081/query with raw SQL (not JSON).
- Start with baseline validation and PRAGMA table_info before assuming column names.
- Use single-quoted string literals in SQL.
- After UPDATE/DELETE, run SELECT save_database().
- See docs/ghidrasql_operational_guide_v1.md for schema details and workflows.
```

### Claude Code

```bash
/plugin marketplace add 0xeb/ghidrasql-skills
```

Ensure the stack is running before the agent connects.

### Codex

Install as a plugin from `plugins/ghidrasql/.codex-plugin/plugin.json` in the ghidrasql-skills repo. Skills are namespaced, e.g. `ghidrasql:connect`, `ghidrasql:decompiler`.

## 3. Skill modules

| Skill | Use when the agent needs to… |
|-------|------------------------------|
| `connect` | Bootstrap session, check endpoints, choose HTTP vs REPL |
| `analysis` | High-level triage — "what does this binary do?" |
| `disassembly` | Functions, instructions, CFG, blocks |
| `xrefs` | Callers, callees, call graph, string refs |
| `data` | Strings, memory bytes, hexdumps |
| `grep` | Find symbols, imports, exports, type names |
| `decompiler` | Pseudocode, locals, parameters |
| `annotations` | Renames, comments, signatures, save workflow |
| `types` | Structs, enums, typedefs, signatures |
| `functions` | SQL helper function catalog |

Full table: section 16 of [ghidrasql_operational_guide_v1.md](ghidrasql_operational_guide_v1.md).

## 4. SQL contract for agents

**Request**

```http
POST /query HTTP/1.1
Host: 127.0.0.1:8081
Content-Type: text/plain; charset=utf-8

SELECT name, printf('0x%X', address) AS addr FROM funcs LIMIT 10
```

**Response:** JSON with query results (or error details).

**Rules agents must follow**

- Use `funcs`, not legacy `functions`, unless `sqlite_master` shows otherwise
- Introspect first: `PRAGMA table_info(funcs);`
- Prefer address-bounded queries over unbounded table scans
- Use single quotes: `printf('0x%X', address)` — not double quotes
- Avoid SQL alias `END` (reserved)
- Writes require explicit save: `SELECT save_database();`

## 5. Recommended agent session flow

```text
1. User imports binary → sets GHIDRA_PROJECT_NAME / GHIDRA_PROGRAM_NAME in .env
2. docker compose up -d
3. Agent runs baseline validation (section 15 of operational guide)
4. Agent introspects schema (section 7)
5. Agent uses targeted SQL (sections 8–10) guided by ghidrasql-skills
6. For renames/comments: read → write → save → verify (section 12)
```

## 6. Giving context to an agent

For a new RE task, provide:

1. Link or path to [ghidrasql_operational_guide_v1.md](ghidrasql_operational_guide_v1.md)
2. Active project/program from `.env`
3. Binary purpose or analysis goal
4. Confirmation that `http://127.0.0.1:8081/query` is reachable

Example prompt:

```text
Analyze the hello binary in project hello_demo.
ghidrasql SQL endpoint: POST http://127.0.0.1:8081/query
Follow docs/ghidrasql_operational_guide_v1.md and ghidrasql-skills.
Start with baseline validation, then list functions and main's pseudocode.
```

## 7. Troubleshooting agent connections

| Symptom | Fix |
|---------|-----|
| Connection refused on :8081 | `docker compose up -d`; check `docker compose ps` |
| Empty funcs/instructions | Binary not imported or analysis incomplete — re-import |
| `success:false` with no error | Wrong column name or double-quoted strings — use PRAGMA |
| Agent can't save renames | Missing `SELECT save_database()` after UPDATE |
| Lock errors | `docker compose down` before import; clear stale `*.lock` files |

See [OPERATIONS.md](OPERATIONS.md) and section 13 of the [operational guide](ghidrasql_operational_guide_v1.md).

## References

- [ghidrasql-skills](https://github.com/0xeb/ghidrasql-skills)
- [ghidrasql](https://github.com/0xeb/ghidrasql)
- [libghidra](https://github.com/0xeb/libghidra)
- [Full operational guide](ghidrasql_operational_guide_v1.md)
