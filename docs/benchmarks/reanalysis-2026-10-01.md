# Offload benchmark: accuracy reanalysis and reproduction

The recorded experiment shows a useful mechanism: Aerospike returns compact
owner-local top-K results instead of shipping candidate posting blobs to the
client. The [historical throughput table](phase-4-results.md) is one
Apple Silicon Docker run, and its full dataset has low exact recall. No new
throughput result is claimed in this reanalysis.

## Recomputed accuracy from the recorded files

`evaluate.py` exhaustively scores every base vector against every query in
float64, using the stored float32 vectors and squared L2. Exact-distance ties
are ordered by VID. It does not build or consult an ANN index. The JSON
artifacts include SHA256 hashes of every input and result file.

| Recorded dataset / mode | Exact recall@10 | Worst query recall | Returned distance mismatches |
|---|---:|---:|---:|
| 100k × 768, 1000 queries: baseline | 0.3886 | 0.0 | 0 |
| 100k × 768: scalar offload | 0.3885 | 0.0 | 0 |
| 100k × 768: NEON offload | 0.3885 | 0.0 | 0 |
| 10k × 64, 200 queries: all three modes | 0.8790 | 0.5 | 0 |

Artifacts: [full recall](evidence/recorded-full-recall-2026-10-01.json),
[quick recall](evidence/recorded-quick-recall-2026-10-01.json).
All 1000 full-dataset queries have recall below 0.99. Direct subtraction and
sum-of-squares independently checked queries 0, 9 and 138; baseline recalls
are 0.3, 0.0 and 0.2 respectively. The evaluator's small exact fixtures cover
perfect hits, missed neighbors, and correct IDs with incorrect distances.

## Why the original parity claim was too strong

The old comparator gave tie credit to any new result with a distance less
than the baseline's worst result. A closer candidate is a candidate-set
change, not necessarily a tie. It also did not reject duplicate/missing IDs,
non-finite distances or mismatched scores for matching IDs, and only printed
the worst query when the *mean* failed. Regression fixtures reproduce these
false passes; the comparator now reports strict overlap separately and only
credits replacements when both displaced and replacement hits are at the
baseline boundary within the documented tolerance.

| Full recorded comparison | Strict mean overlap | Boundary-tolerant mean | Worst | Queries below 0.99 |
|---|---:|---:|---:|---:|
| scalar vs baseline | 0.9994 | 0.9994 | 0.60 | 2 |
| NEON vs baseline | 0.9973 | 0.9974 | 0.80 | 25 |

Artifacts: [scalar](evidence/recorded-scalar-parity-2026-10-01.txt),
[NEON](evidence/recorded-neon-parity-2026-10-01.txt), including the actual
worst-query result lists. No matching-ID distance mismatch was found at
`1e-5 * max(1, |a|, |b|)` tolerance. Scalar query 0 misses four baseline
neighbors whose distances are clearly below the replacement distances. This
rules out a simple boundary-tie explanation for that query; it does not
identify which candidate selection, local truncation, filtering or merge
step lost them. The 0.99 gate is still a **mean overlap** gate, not an
assertion that each query meets 0.99.

The phase-B index is rebuilt on a new in-memory cluster. A seeded dataset
does not establish an identical index: graph construction contains clock-seeded
randomness and multithreaded work. The new harness records index hashes per
phase to expose this confound. Candidate-ID traces around head selection,
owner-local truncation and final merge are required before attributing the
dips to SIMD. No kernel accuracy defect is established by these results.

## Minimal public verification

Docker and network access to public package/repository hosts are required.
Clone source without the unrelated SPACEV LFS dataset, then initialize only
the dependency used by the selected build:

```bash
GIT_LFS_SKIP_SMUDGE=1 git clone -b factory/simd-vector-search https://github.com/dzokha-true/SPTAG.git
cd SPTAG
git submodule update --init ThirdParty/zstd
docker build -t sptag-offload:check .
docker run --rm sptag-offload:check /app/run-offload-tests.sh

# In a sibling checkout:
git clone -b factory/simd-vector-search --recurse-submodules https://github.com/dzokha-true/aerospike-server.git ../aerospike-server
git -C ../aerospike-server fetch --no-recurse-submodules https://github.com/aerospike/aerospike-server.git refs/tags/8.1.1.2:refs/tags/8.1.1.2
docker build -f ../aerospike-server/docker/Dockerfile -t as-vector:check ../aerospike-server
SERVER_IMAGE=as-vector:check SPTAG_IMAGE=sptag-offload:check bash tests/integration/offload/run.sh
```

The fork currently has no release tags, so fetch the public `8.1.1.2` tag
(commit `783cd07537a83bae5aaa851cc1a6f7244e8e3b73`) as above. Use full
server history and tags: a shallow clone can advertise a bare commit
SHA as its version, which the C client rejects before querying. The harness
waits for a nonnegative partition generation and the expected cluster size
from the client network; a listening port alone is insufficient.

The SPTAG Dockerfile pins the public C client to
`550b794adbeffcde52660bfacba4a66f7ba1e616`. CI builds the triggering SPTAG
checkout and the pinned public CE companion, then runs compiled offload unit
tests, evaluator regressions and the seeded end-to-end parity smoke.
The companion server's separate public CI builds its triggering CE checkout,
runs vector and wire tests, and verifies SSE parity actually executes on a
native x86 runner. Neither workflow needs private EE repositories or secrets.
Unsupported AVX2/AVX512 suites may skip; logs/XML preserve that distinction.

## Repeat the experiment, then inspect accuracy

```bash
# Native ARM: request NEON; native x86: use auto or a supported x86 ISA.
SERVER_IMAGE=as-vector:check SPTAG_IMAGE=sptag-offload:check \
  SIMD_KERNEL=neon REPEATS=3 bash tests/benchmark/offload/run.sh quick
# Only after smoke and quick checks pass:
SERVER_IMAGE=as-vector:check SPTAG_IMAGE=sptag-offload:check \
  SIMD_KERNEL=neon REPEATS=5 bash tests/benchmark/offload/run.sh full
```

Each invocation writes a new `tests/benchmark/offload/runs/` directory and
refuses to overwrite an existing `BENCH_WORK` path. It records source/image
identity, warmup and measured logs, phase index hashes, raw results, per-repeat
parity, exact recall, and median/min/max/sample standard deviation of QPS.
Baseline/scalar order alternates between repetitions. These are repeated
searches on the same phase index, **not independent index-build trials**.
The three containers still share one host, and measured wall time includes
Docker startup and index loading; report it as end-to-end invocation QPS.
CPU sampling is coarse and network totals include cluster traffic.

Reanalyse historical files without building either project:

```bash
git lfs pull --include='tests/benchmark/offload/work-*/*.bin' --exclude='datasets/**'
# Python with NumPy installed; no cluster required.
python3 tests/benchmark/offload/evaluate.py \
  tests/benchmark/offload/work-full/base.bin \
  tests/benchmark/offload/work-full/query.bin \
  tests/benchmark/offload/work-full/baseline.bin \
  tests/benchmark/offload/work-full/offload-scalar.bin \
  tests/benchmark/offload/work-full/offload-neon.bin
python3 -m unittest discover -s tests/integration/offload -p 'test_*.py'
python3 -m unittest discover -s tests/benchmark/offload -p 'test_*.py'
```

The historical ARM client computes distances with scalar code; native x86
SPTAG uses its available SIMD kernels. A real distributed-host run, multiple
index seeds, tuned recall targets, steady-state latency distributions, and a
strong native-SIMD client baseline are still needed for a deployment decision.

## Local validation of these changes (2026-10-01)

Both public images built successfully on ARM64. Compiled offload tests passed
10/10 cases (36 assertions), all 10 Python evaluator/readiness/summary
regressions passed, and both workflows passed `actionlint`. The 5000-vector,
64-dimensional single-node smoke passed strict overlap 1.0 for all 100
queries, with no score mismatches and a server log confirming the NEON path.
A client-debug probe reproduced rejection of the tagless server's bare-SHA
version; adding the verified upstream release ancestry fixed the real smoke.

The revised three-node **quick** run completed three measured repetitions
per mode after warmup. All six baseline/offload comparisons had strict
and boundary-tolerant overlap 1.0. Every output had exact recall@10 of
0.879 and zero distance mismatches. Phase index hashes were identical in
this run. [Recall and result hashes](evidence/quick-recall-2026-10-01.json)
and [repeat statistics](evidence/quick-repeats-2026-10-01.json) are retained.

| Quick end-to-end invocation QPS | Median | Min–max | Sample standard deviation |
|---|---:|---:|---:|
| baseline | 720.9 | 695.8–740.2 | 22.3 |
| scalar offload | 739.5 | 703.8–764.0 | 30.3 |
| NEON offload | 711.1 | 684.3–714.9 | 16.7 |

These approximately 0.27-second legs are dominated by invocation overhead;
the overlapping ranges establish **no useful quick-mode speedup**. No CPU
sample completed inside the tiny measured windows, so missing samples are
now reported as `unavailable`, not zero. No new full-dataset timing run was
performed. The full recorded-data accuracy reanalysis above covers all 1000
queries and all 100k base vectors.

The broader existing command `cd /app/Release && ./SPTAGTest` is **not green**:
on this ARM64 build it aborted in `AlgoTest/SPANNTest` with a memory access
violation after two earlier cases passed (173/174 assertions passed before
abort). The public workflow is explicitly scoped to the offload subsystem
and seeded integration, and does not claim full-project test coverage.
Native GitHub-hosted x86 execution remains to be observed after publication;
local image validation here is ARM64.
