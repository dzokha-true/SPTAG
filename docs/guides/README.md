# Engineering guides

Fork documentation for understanding and changing this repository. Upstream user docs (`GettingStart.md`, `Parameters.md`, notebooks) stay under `docs/` at the repo root.

## Read order

1. [CONTEXT.md](../../CONTEXT.md) — domain terms
2. [source-map.md](source-map.md) — what each top-level area owns
3. [build-matrix.md](build-matrix.md) — CMake options and build outputs
4. [testing.md](testing.md) — how tests and benchmarks are organized
5. [../contracts/aerospike-kv-backend.md](../contracts/aerospike-kv-backend.md) — Aerospike KV contract (when using `AEROSPIKEIO`)
6. [../repo-hygiene.md](../repo-hygiene.md) — datasets, scripts, generated files
7. [../change-guide.md](../change-guide.md) — safe modification workflow

## Diataxis map


| Need                                           | Where                                                                                                                                                      |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Learn by doing (build index, search)           | `docs/Tutorial.ipynb`, `docs/examples/QuickstartGuide.ipynb`                                                                                               |
| Task steps (build with Aerospike, run KV test) | [build-matrix.md](build-matrix.md), [testing.md](testing.md)                                                                                               |
| Exact flags, env vars, KV semantics            | [build-matrix.md](build-matrix.md), [../contracts/aerospike-kv-backend.md](../contracts/aerospike-kv-backend.md)                                           |
| Why graph vs postings split                    | [source-map.md](source-map.md), [../adr/0001-aerospike-stores-posting-blobs-not-ann-graph.md](../adr/0001-aerospike-stores-posting-blobs-not-ann-graph.md) |


## Specs and decisions

- Behavior specs (when added): `docs/specs/` — `SPEC-<area>-<nnn>` IDs tied to tests
- Architecture decisions: `docs/adr/`

