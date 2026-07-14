# Check: 009 sptag end-to-end top-K parity (SPEC-4-INTEG-001)

Executor: bash
Spec: docs/spec/aerospike-simd-vector-search.md (in aerospike-server-upstream)
Issue: docs/issues/simd-vector-search/009-sptag-integ-parity.md (in aerospike-server-upstream)
Duration hint: index build + two query passes ~15-30m; not a stall.

## Runnable

- RUN: `SERVER_REPO="/Users/Zhakh/Documents/University/Spring 2026/EC528/aerospike-server-upstream" bash tests/integration/offload/run.sh > .architect/tmp/integ.log 2>&1; s=$?; tail -8 .architect/tmp/integ.log; exit $s` -> exit 0 and output contains `PARITY_OK overlap=` with mean overlap >= 0.99.
- RUN: `grep -c "SPTAG_AS_VECTOR_DISTANCE" tests/integration/offload/run.sh` -> count >= 2 (both legs, flag off and on); exit 0.
- RUN: `ls tests/integration/offload/run.sh` -> harness committed; exit 0.

## Judge-only

- The offload leg proves VECTOR_DISTANCE was actually used (log line or
  server statistic captured in the harness output, quoted in the evidence).
- Dataset/queries seeded; K=10; namespace vector config matches the dataset
  (dim 64, float, l2).
- Failure path dumps both result lists for the worst query.
- Diff confined to the MAY-TOUCH set.
