# Check: 006 sptag docker build verify (forked client, real offload build)

Executor: bash
Spec: docs/spec/aerospike-simd-vector-search.md (in aerospike-server-upstream)
Issue: docs/issues/simd-vector-search/006-sptag-docker-build-verify.md (in aerospike-server-upstream)
Duration hint: first image build ~30-60m; not a stall.

## Runnable

- RUN: `docker build -t sptag-offload-verify:check . > .architect/tmp/db.log 2>&1; s=$?; tail -5 .architect/tmp/db.log; exit $s` -> exit 0.
- RUN: `docker run --rm sptag-offload-verify:check cat /app/build/offload_probe_ok` -> output is exactly `SPTAG_HAS_AEROSPIKE_VECTOR_DISTANCE=1`; exit 0.
- RUN: `docker run --rm sptag-offload-verify:check /app/run-offload-tests.sh 2>&1 | tail -5` -> Boost.Test output contains `No errors detected`; exit 0.
- RUN: `git grep -n "dzokha-true/aerospike-client-c" -- Dockerfile | head -2` -> forked client built from source in the image; exit 0.
- RUN: `git grep -cn "aerospike-client-c_7.3.0" -- Dockerfile; test $? -eq 1 && echo STOCK_CLIENT_REMOVED` -> prints STOCK_CLIENT_REMOVED (stock tarball path gone).

## Judge-only

- Dockerfile fails the build loudly when the vector-distance probe fails
  (cite the mechanism); the probe marker is written only on success.
- run-offload-tests.sh is committed in the repo and COPY'd (not generated
  ad hoc inside the image).
- No changes to `AnnService/inc|src` implementation files or `Test/src/*.cpp`.
