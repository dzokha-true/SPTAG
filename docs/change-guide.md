# Change guide

Workflow for modifying this fork safely and keeping docs aligned with code.

## Before editing

1. Read [CONTEXT.md](../CONTEXT.md) for terms used in issues and commits.
2. Open [guides/source-map.md](guides/source-map.md) and locate the owning directory.
3. For Aerospike or `Storage=AEROSPIKEIO`, read [contracts/aerospike-kv-backend.md](contracts/aerospike-kv-backend.md).

## Making a change

### 1. Scope the boundary

- **Head graph / search** — BKT, KDT, RNG, `VectorIndex`, server socket path.
- **Postings / KV** — `ExtraDynamicSearcher`, `KeyValueIO`, Aerospike adapter.
- **Build** — root `CMakeLists.txt`, `AnnService/CMakeLists.txt`.

Do not move ANN graph data into Aerospike unless an ADR explicitly reverses [adr/0001-aerospike-stores-posting-blobs-not-ann-graph.md](adr/0001-aerospike-stores-posting-blobs-not-ann-graph.md).

### 2. Mark fork deltas

Use comment tag on local changes:

```cpp
// EC528: <short reason>
```

Keep upstream copyright headers. Fork is MIT-licensed like upstream; distributed binaries may still implicate AGPL for linked Aerospike server components — follow course/project legal guidance.

### 3. Spec and test

For observable behavior changes:

1. Add or update `docs/specs/SPEC-<area>-<nnn>.md`.
2. Add or extend a Boost test under `Test/src/`.
3. Set **Verified by** in the spec to the test case name.

Aerospike KV changes should keep `SPEC-KV-001` green when a cluster is available.

### 4. Update reference docs

| Change type | Update |
|-------------|--------|
| CMake option / dependency | [guides/build-matrix.md](guides/build-matrix.md) |
| New module or moved ownership | [guides/source-map.md](guides/source-map.md) |
| KV wire semantics | [contracts/aerospike-kv-backend.md](contracts/aerospike-kv-backend.md) |
| Durable architecture choice | New `docs/adr/` entry |
| Domain term | [CONTEXT.md](../CONTEXT.md) only — no implementation in glossary |

### 5. Verify

```bash
mkdir -p build && cd build
cmake -DAEROSPIKE=ON ..   # when touching Aerospike path
cmake --build . -j
./Release/SPTAGTest
```

Optional Aerospike case:

```bash
export SPTAG_RUN_AEROSPIKE_TEST=1
./Release/SPTAGTest --run_test=KVTest/AerospikeTest
```

## Do not repeat

These approaches were tried and rejected for this project’s latency goals:

| Approach | Why avoided |
|----------|-------------|
| Lua UDF distance on hot query path | Interpreter overhead; poor p99/QPS |
| Policy-only tuning without server distance primitive | No offload without a real VECTOR_DISTANCE-style op |
| Storing or traversing the ANN graph inside Aerospike | Wrong ownership boundary; see ADR 0001 |
| Replacing SPTAG approximate search with server-side brute force | Breaks SPANN design |

## Hard-to-reverse decisions

Write an ADR under `docs/adr/` when:

- Reversing later would be costly
- Future readers will ask “why this way?”
- Real alternatives existed and one was chosen deliberately

Skip ADRs for routine refactors or obvious bug fixes.

## Related

- [guides/README.md](guides/README.md)
- [repo-hygiene.md](repo-hygiene.md)
