# Repository hygiene

What belongs in version control, what should stay local or external, and how to review before deleting files.

## Classification

| Class | Examples | In git? |
|-------|----------|---------|
| **Source** | `AnnService/`, `Test/`, `CMakeLists.txt` | Yes |
| **Upstream docs** | `docs/GettingStart.md`, `docs/Parameters.md`, notebooks | Yes |
| **Fork docs** | `docs/guides/`, `docs/contracts/`, `CONTEXT.md` | Yes |
| **Build output** | `Release/`, `build/`, `x64/`, `*.o` | No — `.gitignore` |
| **Generated / staging** | `artifacts/`, benchmark run outputs | No — `.gitignore` |
| **Dataset blobs** | `datasets/SPACEV1B/*.bin`, sharded `vectors_*.bin` | Prefer LFS or download; see below |
| **AE reproduction** | `Script_AE/**/*.sh`, prebuilt indexes on VM | Scripts yes; data often external |
| **Research tools** | `Tools/OPQ/`, `Tools/nni-auto-tune/` | Yes (code); not primary tests |
| **ThirdParty** | `ThirdParty/zstd`, spdk submodule | Yes (submodules / vendored) |
| **Local test dirs** | `tmp_rocksdb/`, `tmp_aerospike/`, `tmp_file/` | No — created by KVTest |

## Datasets

### `datasets/SPACEV1B/`

| File / dir | Role |
|------------|------|
| `vectors.bin/vectors_*.bin` | ~1.4B × 100-dim int8 document vectors (sharded) |
| `query.bin` | Query vectors |
| `truth.bin` | Ground-truth neighbors |
| `query_log.bin` | Historical queries |
| `README.md`, `LICENSE` | Format docs, O-UDA license |

**Policy options** (pick one for the fork; do not delete shards until decided):

1. **Git LFS** — track `*.bin` with LFS; document `git lfs pull` in clone instructions (upstream README already mentions LFS skip for shallow clones).
2. **External download** — keep README + script; omit blobs from default clone.
3. **Local-only** — add path to `.gitignore`; document expected layout for benchmarks.

Large binaries should not churn in ordinary commits. If shards are missing locally, benchmarks that need full SPACEV1B will not run — that is expected.

### Other data references

- `build_spresh.sh` — may wget datasets for SPFresh experiments
- `Script_AE/README.md` — assumes prebuilt data under `~/data/` on AE VMs

## Scripts vs tests

| Path | Treat as |
|------|----------|
| `Test/src/*.cpp` | Regression / contract verification |
| `Script_AE/**/*.sh` | Paper figure reproduction (hours–days, special hardware) |
| `build_spresh.sh` | Experiment bootstrap, not CI |
| `azure-pipelines.yml` | CI: cmake + `SPTAGTest` only |

## Build and benchmark artifacts

Already ignored (see `.gitignore`):

- `Release/`, `Debug/`, `build/`
- `BenchmarkDotNet.Artifacts/`, `artifacts/`
- Wrappers generated `*wrap.*` outputs

Do not commit compiled binaries or plotted figure outputs from `Script_AE/`.

## Deletion checklist

Before removing a file or directory from the repo:

1. **Purpose** — What used it? (grep for path, check `Script_AE`, INI files, docs.)
2. **License** — Dataset LICENSE must remain if blobs stay referenced.
3. **Regeneration** — Can it be reproduced from documented commands?
4. **Consumers** — Tests, CI, Docker, or scripts that hardcode the path?
5. **Size / LFS** — Will removal break clones that expect LFS pointers?

When in doubt, classify in this doc first; delete in a separate change.

## Related

- [guides/source-map.md](guides/source-map.md)
- [guides/testing.md](guides/testing.md)
