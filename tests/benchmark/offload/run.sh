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
SERVER_REPO="${SERVER_REPO:-$(cd ../../../../aerospike-server-upstream 2>/dev/null && pwd || true)}"
NET=ec528-bench
WORK="$(pwd)/work-$MODE"
NODES=(ec528-b1 ec528-b2 ec528-b3)

cleanup() {
    docker rm -f "${NODES[@]}" ec528-bench-sptag >/dev/null 2>&1 || true
    docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for img in "$SERVER_IMAGE" "$SPTAG_IMAGE"; do
    docker image inspect "$img" >/dev/null 2>&1 || {
        echo "FATAL: image $img missing" >&2; exit 2; }
done

rm -rf "$WORK"
mkdir -p "$WORK/tmp"

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
    for n in "${NODES[@]}"; do
        local ready=0
        for _ in $(seq 1 90); do
            if docker logs "$n" 2>&1 | grep -q "service ready: soon there will be cake"; then
                ready=1; break
            fi
            sleep 2
        done
        [ "$ready" -eq 1 ] || { echo "FATAL: $n not ready" >&2
            docker logs "$n" 2>&1 | tail -15 >&2; exit 1; }
    done
    # Let the mesh settle into one 3-node cluster.
    sleep 5
}

TESTS_ROOT="$(cd ../.. && pwd)"

run_in_sptag() {
    docker run --rm --name ec528-bench-sptag --network "$NET" \
        -v "$WORK":/work -v "$TESTS_ROOT":/harness:ro \
        -e SPTAG_AEROSPIKE_HOST=ec528-b1 -e SPTAG_AEROSPIKE_PORT=3000 \
        -e SPTAG_AS_VECTOR_DISTANCE="$1" \
        "$SPTAG_IMAGE" bash -c "$2"
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

    local cpu_log="$WORK/cpu-$name.log"
    cpu_sampler "$cpu_log" & local sampler=$!

    local net0 t0 t1 net1
    net0=$(net_bytes)
    t0=$(date +%s.%N)
    run_in_sptag "$flag" \
        "cd /work && /app/Release/ssdserving /work/search-$name.ini > /work/ssd-$name.log 2>&1; tail -12 /work/ssd-$name.log"
    t1=$(date +%s.%N)
    net1=$(net_bytes)

    kill "$sampler" 2>/dev/null || true
    wait "$sampler" 2>/dev/null || true

    local wall qps
    wall=$(echo "$t1 $t0" | awk '{printf "%.2f", $1-$2}')
    qps=$(echo "$QUERIES $wall" | awk '{printf "%.1f", $1/$2}')
    local net_mb
    net_mb=$(echo "$net1 $net0" | awk '{printf "%.1f", ($1-$2)/1048576}')
    local cpu_avg
    cpu_avg=$(awk '{gsub("%","",$2); s+=$2; n++} END{if(n) printf "%.0f", s/n; else print 0}' "$cpu_log")

    echo "LEG $name wall=${wall}s qps=$qps node_net_mb=$net_mb avg_node_cpu_pct=$cpu_avg" \
        | tee -a "$WORK/summary.txt"
}

gen_and_build() {
    run_in_sptag 0 "python3.8 /harness/integration/offload/gen_data.py /work $COUNT $QUERIES $DIM"
    sed "s|__DIM__|$DIM|" build.ini.tmpl > "$WORK/build.ini"
    run_in_sptag 0 "cd /work && /app/Release/ssdserving /work/build.ini > /work/ssd-build.log 2>&1; tail -6 /work/ssd-build.log"
}

echo "=== phase A: servers AEROSPIKE_VECTOR_SIMD=scalar ==="
cluster_up scalar
gen_and_build
search_leg 0 baseline
search_leg 1 offload-scalar

echo "=== phase B: servers AEROSPIKE_VECTOR_SIMD=neon ==="
cluster_up neon
gen_and_build
search_leg 1 offload-neon

echo "=== overlap vs baseline ==="
python3 ../../integration/offload/compare.py \
    "$WORK/baseline.bin" "$WORK/offload-scalar.bin" | tee -a "$WORK/summary.txt"
python3 ../../integration/offload/compare.py \
    "$WORK/baseline.bin" "$WORK/offload-neon.bin" | tee -a "$WORK/summary.txt"

echo "=== summary ($MODE) ==="
cat "$WORK/summary.txt"

if [ "$MODE" = "quick" ]; then
    echo "BENCH_OK"
fi
