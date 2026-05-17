# Build matrix

SPTAG builds with **CMake**. There is no top-level Makefile; `make` (or `cmake --build`) runs after `cmake` configures the tree.

## Requirements

| Dependency | Minimum (from CMake / README) |
|------------|-------------------------------|
| CMake | 3.12 |
| Boost | 1.66 (`find_package`); error text mentions 1.67 |
| OpenMP | Required |
| swig | ≥ 4.0.2 (wrappers) |
| GCC (Linux) | ≥ 5.0, C++17 |
| MSVC (Windows) | VS 2019+ (solution build) |

Optional: NUMA (`libnuma`), TBB (default ON), RocksDB, SPDK, io_uring, GPU, Aerospike C client.

## Standard Linux build

```bash
mkdir -p build && cd build
cmake -DSPDK=OFF -DROCKSDB=OFF ..
cmake --build . -j
```

Artifacts land under `Release/` at the **repository root** (CMake sets `EXECUTABLE_OUTPUT_PATH` to `${PROJECT_SOURCE_DIR}/${CMAKE_BUILD_TYPE}/` on non-Windows).

Verify:

```bash
./Release/SPTAGTest
```

## CMake options (root `CMakeLists.txt`)

| Option | Default | Effect |
|--------|---------|--------|
| `GPU` | OFF | GPU support via `GPUSupport/` |
| `LIBRARYONLY` | OFF | Skip `server`, `client`, `indexbuilder`, etc. |
| `ROCKSDB` | OFF | `Storage=ROCKSDBIO`, links RocksDB |
| `SPDK` | OFF | `Storage=SPDKIO`, NVMe/SPDK path |
| `TBB` | ON | Intel TBB |
| `URING` | OFF | io_uring for RocksDB path |
| `AEROSPIKE` | OFF | `Storage=AEROSPIKEIO`, Aerospike C client |
| `USE_ASAN` | OFF | AddressSanitizer (GCC) |

### Aerospike build

Install the [Aerospike C client](https://github.com/aerospike/aerospike-client-c) headers and `libaerospike`, then:

```bash
cd build
cmake -DAEROSPIKE=ON \
  -DAEROSPIKE_DEFAULT_HOST=127.0.0.1 \
  -DAEROSPIKE_DEFAULT_PORT=3000 \
  -DAEROSPIKE_DEFAULT_NAMESPACE=test \
  -DAEROSPIKE_DEFAULT_SET=sptag \
  -DAEROSPIKE_DEFAULT_BIN=value \
  ..
cmake --build . -j
```

If discovery fails, set `AEROSPIKE_INCLUDE_DIR` and `AEROSPIKE_CLIENT_LIBRARY`.

Compile-time defaults can still be overridden at runtime via `SPTAG_AEROSPIKE_*` environment variables (see [aerospike-kv-backend.md](../contracts/aerospike-kv-backend.md)).

`Dockerfile` in the repo root shows an example image with `-DAEROSPIKE=ON`.

## Main targets (`AnnService/CMakeLists.txt`)

| Target | Role |
|--------|------|
| `SPTAGLib` / `SPTAGLibStatic` | Core library |
| `DistanceUtils` | SIMD distance kernels (static) |
| `indexbuilder` / `indexsearcher` | Offline build and search CLI |
| `server` / `client` / `aggregator` | Distributed serving |
| `ssdserving` / `spfresh` | SPANN / SPFresh serving and updates |
| `keyvaluetest` | KV backend utility binary |
| `usefultool` | Misc utilities |
| `SPTAGTest` | Boost.Test suite (`Test/`) |

When `AEROSPIKE=ON`, Aerospike libraries are linked into `SPTAGLib`, `ssdserving`, `spfresh`, `keyvaluetest`, and related targets.

## Optional heavy dependencies

README documents separate builds for:

- **SPDK** — `ThirdParty/spdk` (only if `-DSPDK=ON`)
- **isal-l_crypto** — SPDK dependency
- **RocksDB** — external install (only if `-DROCKSDB=ON`)

Default fork workflow for Aerospike postings: **no SPDK, no RocksDB** unless you need those storage modes.

## Windows

```bash
mkdir build && cd build
cmake -A x64 -DSPDK=OFF -DROCKSDB=OFF ..
```

Open `SPTAG.sln` in Visual Studio 2019+. Run `Test.exe` from the build output. `azure-pipelines.yml` also builds via internal NuGet feeds — that path may not reproduce on a clean fork.

## SPANN index config

Set posting storage in the index INI, for example `benchmark.aerospike.ini`:

```ini
Storage=AEROSPIKEIO
```

Other storage values: `STATIC`, `FILEIO`, `SPDKIO`, `ROCKSDBIO` (see `AnnService/inc/Core/DefinitionList.h`).

## Known friction

- Boost version message mismatch (1.66 vs 1.67) in CMake fatal errors.
- Linux outputs go to repo-root `Release/`, not `build/Release/`.
- Aerospike tests require `-DAEROSPIKE=ON` **and** `SPTAG_RUN_AEROSPIKE_TEST=1` at test runtime.
