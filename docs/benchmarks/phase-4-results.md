# Phase-4 benchmark: baseline vs VECTOR_DISTANCE offload (scalar / NEON)

Run: simd-vector-search, 2026-07-14. Historical single-run measurements.

**Accuracy reanalysis (2026-10-01):** the full dataset has exact recall@10
of 0.3886 / 0.3885 / 0.3885 (baseline / scalar / NEON), despite high overlap
between modes. The original comparator also credited strictly closer
candidates as ties: corrected NEON overlap is 0.9974, worst 0.80. These
results demonstrate reduced posting-transfer overhead at this configuration;
they do not establish production ANN quality or generalizable speedup.
See [reanalysis and reproduction](reanalysis-2026-10-01.md) for checked
artifacts, corrected comparisons, limitations, and current commands.

## Methodology

- Hardware: single Apple Silicon host; Docker Desktop; three asd containers
  (image `as-vector:check`, built from the server factory branch, arm64) in a
  mesh cluster, replication-factor 1, in-memory `test` namespace with
  `vector-dimension 768 / float / l2`; one SPTAG client container
  (`sptag-offload-verify:check`).
- Dataset: seeded synthetic, 100,000 vectors, dim 768, float32, L2; 1000
  seeded queries; K=10. SPANN index built with `Storage=AEROSPIKEIO`
  (postings live in Aerospike; head graph in the client container).
- Harness: `tests/benchmark/offload/run.sh full`. Phase A (servers
  `AEROSPIKE_VECTOR_SIMD=scalar`): baseline leg
  (`SPTAG_AS_VECTOR_DISTANCE=0`, MultiGet + client ComputeDistance) and
  offload-scalar leg (`=1`). Phase B (servers `neon`): offload-neon leg.
  Each phase rebuilds the identical seeded index (in-memory namespace).
  Search: ssdserving, 4 client threads, InternalResultNum=64,
  AsyncMergeInSearch=false.
- Metrics: wall/QPS from the harness; per-node network bytes from
  `/sys/class/net/eth0` deltas summed over the three nodes; CPU sampled via
  `docker stats` every 2 s during each leg; per-query overlap vs the
  baseline leg's top-10 (tie-tolerant).

## Historical results (1000 queries, K=10; original comparator)

| leg | wall | QPS | sum node net bytes | avg node CPU | overlap vs baseline |
|---|---|---|---|---|---|
| baseline (client compute) | 7.02 s | 142.5 | 14,057.7 MB | 19% | 1.0 (self) |
| offload + scalar kernels | 3.28 s | 304.9 | 13.7 MB | 42% | 0.9994 (worst 0.60) |
| offload + NEON kernels | 2.15 s | 465.1 | 13.7 MB | 40% | 0.9986 (worst 0.90) |

Observed ratios in that single run:

- **2.1x / 3.3x throughput** (offload-scalar / offload-NEON vs baseline).
- **~1000x less network traffic**: the baseline ships every candidate
  posting blob (768-dim float vectors) to the client per query; the offload
  ships only owner-local top-K tuples.
- **Compute moved onto the data nodes**: node CPU rises 19% -> ~41% while
  client-side distance work disappears; NEON cuts the server-side scoring
  cost enough for another 1.5x over scalar offload.
- Parity stays above the 0.99 SPEC-4-INTEG-001 gate on both offload legs
  under the original comparator. The cause of the membership differences is
  unresolved; the worst scalar query is not a boundary tie. High mean
  overlap must not be presented as exact nearest-neighbor recall.

## Caveats

- Single physical host: the three "nodes" share CPU, memory bandwidth, and
  the Docker virtual network. Network-byte reductions are structural and
  follow from returning compact results, but the measured byte ratio and
  absolute QPS/latency require independent measurement on real clusters.
- ssdserving's per-query latency table (Avg 4669 baseline vs ~192 offload,
  internal units) has coarse timer resolution on the offload legs; wall/QPS
  above include Docker process startup and index loading. There were no
  repeats, confidence intervals, or steady-state latency measurements.
- arm64 client uses scalar `ComputeDistance` (SPTAG has no NEON client
  kernels); on x86 the baseline client would use SPTAG's AVX kernels,
  narrowing the throughput gap - the network reduction is unaffected.
- Cluster startup on this host occasionally stalls minutes before the
  service port opens; the harness gates on a functional port probe.
- `quick` mode (10k x 64, 200 queries): parity 1.0000 exactly on both legs;
  net bytes 156.1 MB -> 1.1 MB. Its exact recall@10 is 0.879 in every mode.
