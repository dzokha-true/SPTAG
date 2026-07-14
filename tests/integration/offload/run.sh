#!/usr/bin/env bash
# EC528: SPEC-4-INTEG-001 - end-to-end top-K parity, offload vs baseline.
# One asd container (image from the server repo's docker/Dockerfile) plus
# the sptag-offload-verify image: build a small Storage=AEROSPIKEIO index,
# search the same queries with SPTAG_AS_VECTOR_DISTANCE=0 and =1, compare.
# Prints `PARITY_OK overlap=<mean>` on success.
set -euo pipefail

cd "$(dirname "$0")"

SERVER_IMAGE="${SERVER_IMAGE:-as-vector:check}"
SPTAG_IMAGE="${SPTAG_IMAGE:-sptag-offload-verify:check}"
SERVER_REPO="${SERVER_REPO:-$(cd ../../../../aerospike-server-upstream 2>/dev/null && pwd || true)}"
NET=ec528-offload
WORK="$(pwd)/work"

cleanup() {
    docker rm -f ec528-asd ec528-sptag >/dev/null 2>&1 || true
    docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! docker image inspect "$SERVER_IMAGE" >/dev/null 2>&1; then
    if [ -z "$SERVER_REPO" ] || [ ! -f "$SERVER_REPO/docker/Dockerfile" ]; then
        echo "FATAL: $SERVER_IMAGE missing and SERVER_REPO not usable" >&2
        exit 2
    fi
    echo "building $SERVER_IMAGE from $SERVER_REPO..."
    docker build -f "$SERVER_REPO/docker/Dockerfile" -t "$SERVER_IMAGE" \
        "$SERVER_REPO" >/dev/null
fi
if ! docker image inspect "$SPTAG_IMAGE" >/dev/null 2>&1; then
    echo "FATAL: $SPTAG_IMAGE missing - build it from the SPTAG repo root" >&2
    exit 2
fi

rm -rf "$WORK"
mkdir -p "$WORK/tmp"

cleanup || true
docker network create "$NET" >/dev/null
docker run -d --name ec528-asd --network "$NET" \
    -e VECTOR_DIM=64 -e VECTOR_TYPE=float -e VECTOR_METRIC=l2 \
    -e AEROSPIKE_VECTOR_SIMD="${AEROSPIKE_VECTOR_SIMD:-auto}" \
    "$SERVER_IMAGE" >/dev/null

ready=0
for _ in $(seq 1 60); do
    if docker logs ec528-asd 2>&1 | grep -q "service ready: soon there will be cake"; then
        ready=1; break
    fi
    if [ -z "$(docker ps -q -f name=ec528-asd)" ]; then
        echo "FATAL: asd exited early:" >&2
        docker logs ec528-asd 2>&1 | tail -20 >&2
        exit 1
    fi
    sleep 2
done
[ "$ready" -eq 1 ] || { echo "FATAL: asd not ready" >&2; exit 1; }

run_in_sptag() {
    docker run --rm --name ec528-sptag --network "$NET" \
        -v "$WORK":/work \
        -v "$(pwd)":/harness:ro \
        -e SPTAG_AEROSPIKE_HOST=ec528-asd \
        -e SPTAG_AEROSPIKE_PORT=3000 \
        -e SPTAG_AS_VECTOR_DISTANCE="${1}" \
        "$SPTAG_IMAGE" bash -c "${2}"
}

echo "--- generating dataset ---"
run_in_sptag 0 "python3.8 /harness/gen_data.py /work 5000 100 64"

echo "--- building AEROSPIKEIO index (postings -> asd) ---"
run_in_sptag 0 "cd /work && /app/Release/ssdserving /harness/build.ini 2>&1 | tail -8"

search_leg() {
    local flag="$1" out="$2"
    sed "s|RESULT_PATH|$out|" search.ini > "$WORK/search-$out.ini"
    run_in_sptag "$flag" \
        "cd /work && /app/Release/ssdserving /work/search-$out.ini 2>&1 | tail -6"
}

echo "--- baseline leg (MultiGet + ComputeDistance) ---"
search_leg 0 baseline.bin
echo "--- offload leg (VECTOR_DISTANCE) ---"
search_leg 1 offload.bin

echo "--- server-side kernel evidence ---"
docker logs ec528-asd 2>&1 | grep "VECTOR_DISTANCE kernel isa" | tail -1 || {
    echo "FATAL: no VECTOR_DISTANCE kernel log line - offload leg never hit the server op" >&2
    exit 1
}

python3 compare.py "$WORK/baseline.bin" "$WORK/offload.bin"
