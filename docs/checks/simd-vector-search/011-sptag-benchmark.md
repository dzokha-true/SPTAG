# Check: 011 sptag 3-node benchmark

Executor: bash
Spec: docs/spec/aerospike-simd-vector-search.md (in aerospike-server-upstream)
Issue: docs/issues/simd-vector-search/011-sptag-benchmark.md (in aerospike-server-upstream)
Duration hint: quick ~15m; full run ~1-2h (builder-run, results committed).

## Runnable

- RUN: `SERVER_REPO="/Users/Zhakh/Documents/University/Spring 2026/EC528/aerospike-server-upstream" bash tests/benchmark/offload/run.sh quick > .architect/tmp/bench.log 2>&1; s=$?; tail -6 .architect/tmp/bench.log; exit $s` -> exit 0 and output contains `BENCH_OK`.
- RUN: `grep -ci "neon" docs/benchmarks/phase-4-results.md` -> count >= 1; exit 0.
- RUN: `grep -ci "p99" docs/benchmarks/phase-4-results.md` -> count >= 1; exit 0.
- RUN: `grep -ci "overlap" docs/benchmarks/phase-4-results.md` -> count >= 1; exit 0.

## Judge-only

- Results doc contains full-run tables for all three configs (baseline,
  offload-scalar, offload-neon) with p50/p95/p99, QPS, per-node CPU, network
  bytes, and overlap-vs-baseline; methodology and caveats sections present.
- Quick mode is a functional check only and is not presented as a result.
