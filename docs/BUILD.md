# Building ghidrasql-ai

## Ghidra version: 12.0.4 (validated default)

This release pins **Ghidra 12.0.4 PUBLIC** — the same version used in the original working `ghidra-ai` setup (`ghidra-base:local` built from `ghidra_12.0.4_PUBLIC`).

| Source | Stated requirement |
|--------|-------------------|
| [libghidra README](https://github.com/0xeb/libghidra) | Ghidra **12.0.4+** |
| [ghidrasql install-prompt.md](https://github.com/0xeb/ghidrasql/blob/main/install-prompt.md) | Ghidra **12.1+** (upstream docs; not what this stack was validated against) |

**Default: 12.0.4.** The dev image was built and tested on 12.0.4 with libghidra, libxsql, ghidrasql, and the ranged-scan patches. You can try 12.1.2 via build args (see below) if you want to align with upstream ghidrasql docs.

### Historical build errors (not a Ghidra version issue)

The first `ghidra-ai` Docker builds failed during **cmake compile** of the ghidrasql patch, with:

```text
error: 'MemoryBlock' is not a member of 'libghidra::client'; did you mean 'MemoryBlockRecord'?
```

That was a typo in an early inline Dockerfile patch (`MemoryBlock` vs `MemoryBlockRecord`), fixed in the dev tree by `fix_ghidra_funcs_patch_type.sh`. The release `docker/patch-ghidrasql-source.py` uses `MemoryBlockRecord` throughout and includes a safety fix for the old typo.

Those errors are unrelated to choosing 12.0.4 vs 12.1.2.

## Build methods

### A. Download release (default)

```bash
./build.sh
# or: build.bat
```

Downloads Ghidra **12.0.4** from GitHub, verifies SHA-256, builds both images.

### B. Local Ghidra tree (recommended if you already have the zip extracted)

```bash
./build.sh --local ../ghidra_12.0.4_PUBLIC
# Windows: build.bat --local ..\ghidra_12.0.4_PUBLIC
```

Uses `Dockerfile.base.local` — skips download; matches the original dev workflow.

### C. Override Ghidra version (optional)

To try 12.1.2 instead:

```bash
docker build -f Dockerfile.base \
  --build-arg GHIDRA_VERSION=12.1.2 \
  --build-arg GHIDRA_RELEASE=20260605 \
  --build-arg GHIDRA_SHA256=b62e81a0390618466c019c60d8c2f796ced2509c4c1aea4a37644a77272cf99d \
  -t ghidrasql-ai-base:latest .
docker build -f Dockerfile -t ghidrasql-ai:latest .
```

## Common build failures

### 1. `Dockerfile.base` — download or SHA-256

```text
sha256sum: WARNING: 1 computed checksum did NOT match
```

Re-download or use `--local ../ghidra_12.0.4_PUBLIC`.

### 2. `patch-ghidrasql-source.py` — patch not found

```text
ERROR: Could not find original read_functions block
```

Upstream ghidrasql changed. Pin `GHIDRASQL_REF` in `Dockerfile` or update the patch script.

### 3. CMake — protobuf `port.h` warnings (usually harmless)

Long `-Wmissing-requires` spam from protobuf while building is **normal** and not the failure:

```text
protobuf/port.h:181:5: warning: testing if a concept-id is a valid expression ... [-Wmissing-requires]
```

Scroll past those and find the first line containing **`error:`**. Common real errors:

**`MemoryBlock` is not a member of `libghidra::client`**

Early patch typo — fixed in `docker/patch-ghidrasql-source.py`. Rebuild with `--no-cache`:

```bash
docker build --no-cache -f Dockerfile -t ghidrasql-ai:latest .
```

**`redeclaration of 'const auto end'`** in `read_functions`

GCC range-for can clash with a local variable named `end`. The patch now uses `range_end` (same as the instructions/symbols/xrefs patches).

**`'dest' was not declared in this scope`** in `read_symbols`

Copy-paste bug in an early patch draft (`dest.push_back` instead of `out.push_back`). Fixed in `docker/patch-ghidrasql-source.py`.

**`ninja: subcommand failed` with only warnings shown**

The actual error is usually a few lines above, often in `source_libghidra.cpp.o`. Re-run with plain output:

```bash
docker build --no-cache --progress=plain -f Dockerfile -t ghidrasql-ai:latest . 2>&1 | tee build.log
grep -i error build.log | head -20
```

### 4. Gradle — `installExtension` failed

Confirm base image:

```bash
docker run --rm ghidrasql-ai-base:latest ls /ghidra/support/analyzeHeadless
```

### 5. `make-postgres.sh` failed (base image)

Allocate more memory to Docker, or use `--local` from an extracted tree.

## Pinning upstream refs

`Dockerfile` defaults to `main` for libghidra and ghidrasql. Pin commits for reproducibility:

```bash
docker build -f Dockerfile \
  --build-arg LIBGHIDRA_REF=abc123 \
  --build-arg GHIDRASQL_REF=def456 \
  -t ghidrasql-ai:latest .
```

## Verify after build

```bash
docker run --rm ghidrasql-ai:latest ghidrasql --help
docker run --rm ghidrasql-ai:latest test -f /opt/ghidrasql/scripts/LibGhidraHeadlessServer.java
```
