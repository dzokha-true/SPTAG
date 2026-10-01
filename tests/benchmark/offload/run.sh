#!/usr/bin/env bash
# EC528: 3-node benchmark - baseline (client MultiGet+ComputeDistance) vs
# offload+scalar vs offload+NEON. `run.sh quick` is the functional gate
# (prints BENCH_OK); `run.sh full` produces the numbers for
# docs/benchmarks/phase-4-results.md.
#
# The namespace is in-memory, so each server configuration phase rebuilds
# the (seeded, identical) index: phase A (scalar servers) hosts the baseline
# and offload-scalar legs; phase B (neon servers) hosts the offload-neon leg.
set -euo pipefail

cd "$(dirname "$0")"

MODE="${1:-quick}"
case "$MODE" in
    quick) COUNT=10000; QUERIES=200; DIM=64 ;;
    full)  COUNT=100000; QUERIES=1000; DIM=768 ;;
    *) echo "usage: run.sh [quick|full]" >&2; exit 2 ;;
esac

SERVER_IMAGE="${SERVER_IMAGE:-as-vector:check}"
SPTAG_IMAGE="${SPTAG_IMAGE:-sptag-offload-verify:check}"
REPEATS="${REPEATS:-3}"
SIMD_KERNEL="${SIMD_KERNEL:-auto}"
[[ "$REPEATS" =~ ^[1-9][0-9]*$ ]] || { echo "REPEATS must be positive" >&2; exit 2; }
[[ "$SIMD_KERNEL" =~ ^(auto|neon|sse|avx2|avx512)$ ]] || { echo "invalid SIMD_KERNEL" >&2; exit 2; }
NET=ec528-bench
# Preserve historical fixtures and every new run; refuse an existing output path.
WORK="${BENCH_WORK:-$(pwd)/runs/$MODE-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
[[ "$WORK" = /* ]] || { echo "BENCH_WORK must be absolute" >&2; exit 2; }
[ ! -e "$WORK" ] || { echo "refusing to overwrite $WORK" >&2; exit 2; }
NODES=(ec528-b1 ec528-b2 ec528-b3)
SAMPLER=""

cleanup() {
    if [ -n "$SAMPLER" ]; then kill "$SAMPLER" 2>/dev/null || true; wait "$SAMPLER" 2>/dev/null || true; SAMPLER=""; fi
    if [ -d "$WORK" ]; then
        for n in "${NODES[@]}"; do
            docker logs "$n" > "$WORK/last-$n.log" 2>&1 || true
            docker inspect "$n" > "$WORK/last-$n-inspect.json" 2>/dev/null || true
        done
    fi
    docker rm -f "${NODES[@]}" ec528-bench-sptag >/dev/null 2>&1 || true
    docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for img in "$SERVER_IMAGE" "$SPTAG_IMAGE"; do
    docker image inspect "$img" >/dev/null 2>&1 || {
        echo "FATAL: image $img missing" >&2; exit 2; }
done

mkdir -p "$WORK/tmp"
{
    echo "mode=$MODE vectors=$COUNT queries=$QUERIES dim=$DIM seed=528 repeats=$REPEATS kernel=$SIMD_KERNEL"
    echo "SPTAG source $(git rev-parse HEAD)"
    git status --short
    uname -a
    docker image inspect --format '{{.Id}} {{.Architecture}} {{json .RepoDigests}}' "$SERVER_IMAGE" "$SPTAG_IMAGE"
    docker info --format 'Docker={{.ServerVersion}} CPUs={{.NCPU}} Memory={{.MemTotal}}'
} > "$WORK/environment.txt"
echo "BENCH_WORK=$WORK"

cluster_up() {
    local simd="$1"
    cleanup || true
    docker network create "$NET" >/dev/null
    local seeds="ec528-b1:3002 ec528-b2:3002 ec528-b3:3002"
    local idx=1
    for n in "${NODES[@]}"; do
        docker run -d --name "$n" --network "$NET" \
            -e VECTOR_DIM="$DIM" -e VECTOR_TYPE=float -e VECTOR_METRIC=l2 \
            -e REPLICATION_FACTOR=1 \
            -e NODE_ID="b$idx" -e MESH_SEED="$seeds" \
            -e AEROSPIKE_VECTOR_SIMD="$simd" \
            "$SERVER_IMAGE" >/dev/null
        idx=$((idx+1))
    done
    docker run --rm --network "$NET" -v "$TESTS_ROOT":/harness:ro \
        "$SPTAG_IMAGE" python3.8 /harness/integration/offload/wait_ready.py \
        --nodes 3 "${NODES[@]}"

}

TESTS_ROOT="$(cd ../.. && pwd)"

run_in_sptag() {
    docker run --rm --name ec528-bench-sptag --network "$NET" \
        -v "$WORK":/work -v "$TESTS_ROOT":/harness:ro \
        -e SPTAG_AEROSPIKE_HOST=ec528-b1 -e SPTAG_AEROSPIKE_PORT=3000 \
        -e SPTAG_AS_VECTOR_DISTANCE="$1" \
        "$SPTAG_IMAGE" bash -euo pipefail -c "$2"
}

net_bytes() {
    local total=0
    for n in "${NODES[@]}"; do
        local rx tx
        rx=$(docker exec "$n" cat /sys/class/net/eth0/statistics/rx_bytes)
        tx=$(docker exec "$n" cat /sys/class/net/eth0/statistics/tx_bytes)
        total=$((total + rx + tx))
    done
    echo "$total"
}

cpu_sampler() {
    # background: sample per-node CPU% every 2s into $1 until killed
    local out="$1"
    while :; do
        docker stats --no-stream --format '{{.Name}} {{.CPUPerc}}' \
            "${NODES[@]}" >> "$out" 2>/dev/null || true
        sleep 2
    done
}

search_leg() {
    local flag="$1" name="$2"
    sed -e "s|RESULT_PATH|$name.bin|" -e "s|__DIM__|$DIM|" \
        search.ini.tmpl > "$WORK/search-$name.ini"

    # Untimed warmup per leg; measured wall time still includes process startup
    # and index load, so it is an end-to-end invocation rate, not steady-state QPS.
    run_in_sptag "$flag" "cd /work && /app/Release/ssdserving /work/search-$name.ini > /work/warmup-$name.log 2>&1"
    local cpu_log="$WORK/cpu-$name.log"
    cpu_sampler "$cpu_log" & SAMPLER=$!

    local net0 t0 t1 net1
    net0=$(net_bytes)
    t0=$(python3 -c 'import time; print(time.monotonic())')
    run_in_sptag "$flag" \
        "cd /work && /app/Release/ssdserving /work/search-$name.ini > /work/ssd-$name.log 2>&1; tail -12 /work/ssd-$name.log"
    t1=$(python3 -c 'import time; print(time.monotonic())')
    net1=$(net_bytes)

    kill "$SAMPLER" 2>/dev/null || true
    wait "$SAMPLER" 2>/dev/null || true
    SAMPLER=""

    local wall qps
    wall=$(echo "$t1 $t0" | awk '{printf "%.6f", $1-$2}')
    qps=$(echo "$QUERIES $wall" | awk '{printf "%.1f", $1/$2}')
    local net_mb
    net_mb=$(echo "$net1 $net0" | awk '{printf "%.1f", ($1-$2)/1048576}')
    local cpu_avg
    cpu_avg=$(awk '{gsub("%","",$2); s+=$2; n++} END{if(n) printf "%.0f", s/n; else print "unavailable"}' "$cpu_log")

    echo "LEG $name wall=${wall}s qps=$qps node_net_mb=$net_mb avg_node_cpu_pct=$cpu_avg" \
        | tee -a "$WORK/summary.txt"
}

gen_and_build() {
    run_in_sptag 0 "python3.8 /harness/integration/offload/gen_data.py /work $COUNT $QUERIES $DIM"
    sed "s|__DIM__|$DIM|" build.ini.tmpl > "$WORK/build.ini"
    run_in_sptag 0 "cd /work && /app/Release/ssdserving /work/build.ini > /work/ssd-build-$1.log 2>&1; tail -6 /work/ssd-build-$1.log"
    python3 - "$WORK/index" > "$WORK/index-$1.sha256" <<'HASH'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
for path in sorted(root.rglob('*')):
    if path.is_file():
        print(hashlib.sha256(path.read_bytes()).hexdigest(), path.relative_to(root))
HASH
}

echo "=== phase A: servers AEROSPIKE_VECTOR_SIMD=scalar ==="
cluster_up scalar
gen_and_build scalar
for r in $(seq 1 "$REPEATS"); do
    # Alternate baseline/offload order to reduce systematic warm-cache bias.
    if (( r % 2 )); then
        search_leg 0 "baseline-r$r"
        search_leg 1 "offload-scalar-r$r"
    else
        search_leg 1 "offload-scalar-r$r"
        search_leg 0 "baseline-r$r"
    fi
done
for n in "${NODES[@]}"; do docker logs "$n" > "$WORK/server-scalar-$n.log" 2>&1; done

echo "=== phase B: servers AEROSPIKE_VECTOR_SIMD=$SIMD_KERNEL ==="
cluster_up "$SIMD_KERNEL"
gen_and_build "$SIMD_KERNEL"
for r in $(seq 1 "$REPEATS"); do search_leg 1 "offload-$SIMD_KERNEL-r$r"; done
for n in "${NODES[@]}"; do docker logs "$n" > "$WORK/server-$SIMD_KERNEL-$n.log" 2>&1; done

echo "=== overlap vs baseline (each repetition) ==="
for r in $(seq 1 "$REPEATS"); do
    for leg in offload-scalar "offload-$SIMD_KERNEL"; do
        python3 ../../integration/offload/compare.py \
            "$WORK/baseline-r$r.bin" "$WORK/$leg-r$r.bin" | tee -a "$WORK/summary.txt"
    done
done
python3 summarize.py "$WORK/summary.txt" | tee "$WORK/repeated-summary.json"
# Compute exact recall outside the timed interval, using the image's NumPy.
run_in_sptag 0 "python3.8 /harness/benchmark/offload/evaluate.py /work/base.bin /work/query.bin /work/baseline-r*.bin /work/offload-*-r*.bin > /work/recall.json"
python3 - "$WORK/recall.json" <<'CHECK'
import json, sys
with open(sys.argv[1]) as stream:
    results = json.load(stream)['results']
assert all(row['distance_mismatches'] == 0 for row in results), 'returned distances disagree with exact L2 oracle'
CHECK
echo "Artifacts: $WORK (recall.json, repeated-summary.json, logs, result binaries)"
if [ "$MODE" = "quick" ]; then echo "BENCH_OK"; fi
