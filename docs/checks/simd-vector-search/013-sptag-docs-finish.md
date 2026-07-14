# Check: 013 sptag docs finish

Executor: bash
Spec: docs/spec/aerospike-simd-vector-search.md (in aerospike-server-upstream)
Issue: docs/issues/simd-vector-search/013-sptag-docs-finish.md (in aerospike-server-upstream)

## Runnable

- RUN: `git grep -in "synchronous\|async" -- docs/adr/0002-server-side-vector-distance-offload.md | head -3` -> V1 sync decision recorded; exit 0.
- RUN: `ls docs/solutions | head -10` -> at least one solutions entry; exit 0.
- RUN: `git grep -n "run-offload-tests\|offload_probe_ok" -- docs/contracts/aerospike-kv-backend.md | head -2` -> contract reflects the verified build path; exit 0.

## Judge-only (orchestrator-graded; no cold judge for the finish docs job)

- Docs statements match run artifacts; glossary consistent with shipped
  behavior.
