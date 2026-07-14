# ADR 0002: Server-side vector distance offload

## Status

Accepted

## Context

Baseline `Storage=AEROSPIKEIO` fetches posting blobs from Aerospike, then SPTAG parses tail vectors and runs `ComputeDistance` in the client process. EC528 Aerospike client/server code adds a `VECTOR_DISTANCE` operation that can score listed posting records on the partition owner.

Alternatives considered:

- Keep all tail-vector scoring in SPTAG.
- Move full SPANN graph traversal into Aerospike.
- Add more wire protocol changes before first offload integration.

## Decision

- SPTAG keeps head graph traversal and global top-K merge.
- Aerospike scores listed posting records and returns owner-local top-K hits plus per-key statuses.
- V1 applies only to normal SPANN `SearchIndex`.
- Iterative search, filter search, and debug truth/found flows stay on the baseline `MultiGet + ComputeDistance` path.
- If offload is enabled but the EC528 client API is unavailable or an offload request fails, SPTAG fails fast. It does not silently fall back.
- This SPTAG change does not add a new server/client protocol; it consumes the existing EC528 Aerospike `VECTOR_DISTANCE` API.

## Consequences

- V1 is synchronous from SPTAG's perspective: `AerospikeKeyValueIO::
  VectorDistance` issues one client call (`aerospike_vector_distance`, which
  fans out per partition owner internally with `policy.concurrent`); the
  `AsyncReadRequest` parameter is accepted but unused. Revisit only if the
  measured request latency warrants pipelining across queries.
- Verified end-to-end (run simd-vector-search): SPEC-4-INTEG-001 per-query
  top-10 overlap 1.0000 vs the baseline path on a live 3-node cluster;
  server-side kernel ISA logged (`neon` on arm64).
- Quantized indexes are refused by the offload path (fail fast before any
  KV call): the wire query must be raw `dim * sizeof(ValueType)` bytes,
  while a quantizer encodes the query target to `IQuantizer::QuantizeSize()`
  bytes. Disable `VectorDistanceOffload` or the quantizer.

- `Storage=AEROSPIKEIO` remains a posting-list backend, not a full ANN graph backend.
- Index configuration and Aerospike namespace vector configuration must agree before offload is enabled.
- Offload observability is limited to request latency and returned hit counts in V1.

## References

- `AnnService/inc/Core/SPANN/ExtraDynamicSearcher.h`
- `AnnService/inc/Core/SPANN/VectorDistanceOffload.h`
- `AnnService/inc/Helper/AerospikeKeyValueIO.h`
- `AnnService/src/Helper/AerospikeKeyValueIO.cpp`
