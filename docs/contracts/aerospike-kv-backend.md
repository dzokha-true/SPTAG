# Contract: Aerospike KV backend

SPTAG-side contract for `Helper::AerospikeKeyValueIO` when SPANN `Storage=AEROSPIKEIO`. This describes the **client** adapter in this repository, not Aerospike server features.

**Implementation:** `AnnService/inc/Helper/AerospikeKeyValueIO.h`, `AnnService/src/Helper/AerospikeKeyValueIO.cpp`  
**Construction:** `AnnService/inc/Core/SPANN/ExtraDynamicSearcher.h`  
**Reference test:** `Test/src/KVTest.cpp` (`KVTest/AerospikeTest`)

## Record model

| Field | Value |
|-------|--------|
| Key | `int64` user key = SPTAG `SizeType` head ID |
| Namespace | Configurable (default `test`) |
| Set | Configurable (default `sptag`) |
| Value bin | Single bytes bin (default name `value`) |
| Payload | Opaque posting blob; format owned by SPANN posting encoder, not interpreted by Aerospike |

No secondary indexes or graph structure are stored in Aerospike for this mode.

## Configuration

### CMake compile-time defaults (`-DAEROSPIKE=ON`)

| Cache variable | Default |
|----------------|---------|
| `AEROSPIKE_DEFAULT_HOST` | `127.0.0.1` |
| `AEROSPIKE_DEFAULT_PORT` | `3000` |
| `AEROSPIKE_DEFAULT_NAMESPACE` | `test` |
| `AEROSPIKE_DEFAULT_SET` | `sptag` |
| `AEROSPIKE_DEFAULT_BIN` | `value` |

Defines `SPTAG_AEROSPIKE_DEFAULT_*` macros used when env vars are unset.

### Runtime environment (override defaults)

| Variable | Purpose |
|----------|---------|
| `SPTAG_AEROSPIKE_HOST` | Cluster host |
| `SPTAG_AEROSPIKE_PORT` | Cluster port (invalid values fall back to compile default in `ExtraDynamicSearcher`; `KVTest` logs a warning) |
| `SPTAG_AEROSPIKE_NAMESPACE` | Namespace |
| `SPTAG_AEROSPIKE_SET` | Set name |
| `SPTAG_AEROSPIKE_BIN` | Bytes bin name for posting payload |
| `SPTAG_AEROSPIKE_USER` | Optional username |
| `SPTAG_AEROSPIKE_PASSWORD` | Optional password |
| `SPTAG_AS_VECTOR_DISTANCE` | Optional offload override; accepts `1/true/yes/on` and `0/false/no/off` |

### Index INI

```ini
Storage=AEROSPIKEIO
VectorDistanceOffload=false
```

See `benchmark.aerospike.ini` for a full benchmark example.

## Operations

All operations require a successful `aerospike_connect` (`Available() == true`). Otherwise methods return `ErrorCode::Fail`.

| Method | Aerospike API | Semantics |
|--------|---------------|-----------|
| `Get` | `aerospike_key_get` | Read full bytes bin into `std::string` or `PageBuffer` |
| `MultiGet` | `aerospike_batch_get` | One batch read; per-key failure fails whole call |
| `Put` | `aerospike_key_put` | Replace bin with raw bytes |
| `Merge` | `aerospike_key_operate` append | `as_operations_add_append_raw` on value bin; empty value → success no-op |
| `Delete` | `aerospike_key_remove` | `AEROSPIKE_ERR_RECORD_NOT_FOUND` treated as success |
| `VectorDistance` | `aerospike_vector_distance` | Optional EC528 offload API; scores requested head posting records and returns scored hits plus per-key statuses |
| `Checkpoint` | — | No-op success (persistence is server-side) |
| `ShutDown` | `aerospike_close` / `aerospike_destroy` | Close client |

### Merge fallback

If append operate returns `AEROSPIKE_ERR_RECORD_NOT_FOUND`, implementation **Put**s the merge bytes as a new record (same as create-on-first-append).

Checksum callback parameter on `Merge` is accepted but not used for Aerospike-specific validation.

### Timeouts

Microsecond timeout converted to milliseconds for Aerospike policies (`total_timeout` and `socket_timeout`). `MaxTimeout` maps to `0` ms in policy (client default behavior).

## Error handling

- Connection and per-operation failures log via `SPTAGLIB_LOG` and `fprintf(stderr, ...)`.
- `Get` / `MultiGet`: missing bin or invalid bytes → `ErrorCode::Fail`.
- `Delete`: not-found → `ErrorCode::Success`.

## Verification

**Build:**

```bash
cmake -DAEROSPIKE=ON .. && cmake --build . -j
```

**Run** (Aerospike server must accept the configured namespace/set):

```bash
export SPTAG_RUN_AEROSPIKE_TEST=1
./Release/SPTAGTest --run_test=KVTest/AerospikeTest
```

**Spec ID:** `SPEC-KV-001` (see `docs/specs/SPEC-KV-001.md`)

## Out of scope (this contract)

- ANN graph storage or traversal in Aerospike
- New server/client protocol for distance offload
- Lua UDFs on the query path


## Verified build & harness entry points (run simd-vector-search)

- Docker image: `docker build -t sptag-offload-verify:check .` builds the
  forked client from branch `ec528/modules-abs-path` (stock tarball removed),
  fails loudly if the `aerospike_vector_distance.h` probe fails, and writes
  `/app/build/offload_probe_ok` (`SPTAG_HAS_AEROSPIKE_VECTOR_DISTANCE=1`)
  only on success. `/app/run-offload-tests.sh` runs the
  `VectorDistanceOffloadTest` Boost suite (10 cases / 36 assertions).
- End-to-end parity: `bash tests/integration/offload/run.sh` ->
  `PARITY_OK overlap=1.0000` (SPEC-4-INTEG-001).
- Benchmark: `bash tests/benchmark/offload/run.sh quick|full` ->
  baseline vs offload-scalar vs offload-neon; results in
  `docs/benchmarks/phase-4-results.md`.
- arm64: the whole stack builds/runs on aarch64 (scalar client kernels);
  see `docs/solutions/arm64-port-and-client-modules-path.md`.
