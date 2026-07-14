# Check: 007 sptag quantizer guard

Executor: bash
Spec: docs/spec/aerospike-simd-vector-search.md (in aerospike-server-upstream)
Issue: docs/issues/simd-vector-search/007-sptag-quantizer-guard.md (in aerospike-server-upstream)
Duration hint: cached rebuild ~10-20m.

## Runnable

- RUN: `docker build -t sptag-offload-verify:check . > .architect/tmp/db.log 2>&1; s=$?; tail -4 .architect/tmp/db.log; exit $s` -> exit 0 (rebuild with the guard).
- RUN: `docker run --rm sptag-offload-verify:check /app/run-offload-tests.sh 2>&1 | tail -5` -> `No errors detected` with a strictly larger test-case count than the issue-006 baseline run (new quantizer/size tests ran).
- RUN: `git grep -in "quantizer" -- AnnService/inc/Core/SPANN/VectorDistanceOffload.h AnnService/inc/Core/SPANN/ExtraDynamicSearcher.h | head -6` -> guard present in the offload path; exit 0.
- RUN: `git grep -in "quantizer" -- Test/src/VectorDistanceOffloadTest.cpp | head -3` -> tests present; exit 0.
- RUN: `git grep -in "quantizer" -- docs/adr/0002-server-side-vector-distance-offload.md | head -2` -> ADR consequence recorded; exit 0.

## Judge-only

- Run() verifies the outgoing byte length equals dim * sizeof(ValueType) and
  errors on mismatch without calling the KV backend (cite file:line and the
  fake's call-recording evidence).
- Fail-fast pattern matches the existing guards (unavailable flag + LL_Error),
  no silent fallback.
