# ADR 0001: Aerospike stores posting blobs, not the ANN graph

## Status

Accepted

## Context

SPANN query path has two phases: (1) coarse search over an in-memory relative neighborhood graph on head vectors, and (2) fetch and score tail vectors in posting lists. The fork uses Aerospike as a durable KV store for postings (`Storage=AEROSPIKEIO`) via `AerospikeKeyValueIO`.

Alternatives considered:

- Store graph edges and head vectors in Aerospike and traverse on the server
- Run full brute-force search in Aerospike
- Use Lua UDFs for per-vector distance on the hot path

## Decision

- **SPTAG retains** head graph (BKT/KDT + RNG), graph traversal, and `ComputeDistance` on posting bytes in the client process (baseline), with optional future server-side distance on tail bytes in Aerospike bins.
- **Aerospike stores** opaque posting-list blobs keyed by head ID (namespace/set/bin configurable). Operations: Get, MultiGet, Put, Merge (append), Delete.

## Consequences

- Index folder still supplies `graph.bin` and head structures for load; Aerospike is not a drop-in replacement for the whole index.
- Integration work focuses on KV latency, batch MultiGet, and eventual VECTOR_DISTANCE — not graph algorithms in the database.
- Documentation and contracts live in `docs/contracts/aerospike-kv-backend.md` and glossary terms in `CONTEXT.md`.

## References

- `AnnService/inc/Core/SPANN/ExtraDynamicSearcher.h`
- `AnnService/src/Helper/AerospikeKeyValueIO.cpp`
- [../guides/source-map.md](../guides/source-map.md)
