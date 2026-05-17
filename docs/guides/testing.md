# Testing

How verification is organized in this repo and how it differs from paper reproduction scripts.

## Unit and integration tests

**Framework:** [Boost.Test](https://www.boost.org/doc/libs/release/libs/test/)  
**Binary:** `Release/SPTAGTest` (Linux; `Test.exe` on Windows)  
**Sources:** all `Test/src/*.cpp` globbed in `Test/CMakeLists.txt`

CMake does **not** register CTest targets; CI and local verify run the executable directly:

```bash
cd build && cmake .. && cmake --build . -j
./Release/SPTAGTest
```

`azure-pipelines.yml` uses the same pattern (`cd ../Release && ./SPTAGTest`).

## Test categories

| Category | Location | When it runs |
|----------|----------|----------------|
| Core / index | `Test/src/*Test.cpp` (excluding below) | Default build |
| KV backends | `Test/src/KVTest.cpp` | Backend-specific; Aerospike opt-in |
| Performance | `Test/src/PerfTest.cpp` | Part of `SPTAGTest` |
| SPFresh / config benchmarks | `Test/src/SPFreshTest.cpp` | Uses `BENCHMARK_CONFIG` env when set |
| GPU | `Test/cuda/`, `GPUSupport/` | `-DGPU=ON` |

### KVTest backends

`KVTest.cpp` exercises `KeyValueIO` implementations:

| Case | CMake flag | Notes |
|------|------------|--------|
| `FileTest` | always | Local file controller under `tmp_file/` |
| `RocksDBTest` | `-DROCKSDB=ON` | `tmp_rocksdb/` |
| `SPDKTest` | `-DSPDK=ON` | `tmp_spdk/` |
| `AerospikeTest` | `-DAEROSPIKE=ON` | See below |

Flow per backend: Put many keys → Merge → Get → MultiGet search loop → Delete.

## Aerospike KV test

**Build:**

```bash
cmake -DAEROSPIKE=ON ..
cmake --build . -j
```

**Runtime:** tests skip unless opted in:

```bash
export SPTAG_RUN_AEROSPIKE_TEST=1
# optional overrides — see contracts doc
export SPTAG_AEROSPIKE_HOST=127.0.0.1
export SPTAG_AEROSPIKE_PORT=3000
./Release/SPTAGTest --run_test=KVTest/AerospikeTest
```

Without `AEROSPIKE` at compile time, the case logs a skip message. Without `SPTAG_RUN_AEROSPIKE_TEST=1`, it skips to avoid failing CI when no cluster is present.

## Benchmarks vs tests

| Kind | Path | Purpose |
|------|------|---------|
| In-tree benchmark tests | `Test/src/SPFreshTest.cpp`, `PerfTest.cpp` | Automated timing/recall checks inside Boost |
| Paper AE scripts | `Script_AE/**/*.sh` | Multi-hour figure reproduction; needs hardware/datasets |
| NNI tuning | `Tools/nni-auto-tune/` | Hyperparameter search |
| Example INI | `benchmark.aerospike.ini` | SPANN benchmark config with `Storage=AEROSPIKEIO` |

Do not treat `Script_AE/` shell scripts as the primary regression suite.

## Adding a behavior spec

1. Add or extend `docs/specs/SPEC-<area>-<nnn>.md` describing observable behavior.
2. Add a Boost test that fails before the fix and passes after.
3. Record the test path in the spec’s **Verified by** section.

See [change-guide.md](../change-guide.md).

## Related

- [build-matrix.md](build-matrix.md)
- [../contracts/aerospike-kv-backend.md](../contracts/aerospike-kv-backend.md)
