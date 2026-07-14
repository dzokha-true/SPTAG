#!/usr/bin/env bash
# EC528: run the VECTOR_DISTANCE offload Boost.Test suite inside the image.
# Success output includes Boost's "No errors detected"; nonzero exit on any
# failure. Used by the frozen checks for issues #6/#7.
set -euo pipefail

BIN=/app/Release/SPTAGTest

if [ ! -x "$BIN" ]; then
    echo "FATAL: SPTAGTest binary missing at $BIN" >&2
    exit 2
fi

if [ ! -f /app/build/offload_probe_ok ]; then
    echo "FATAL: offload probe marker missing - build is not offload-real" >&2
    exit 3
fi

exec "$BIN" --run_test=VectorDistanceOffloadTest --log_level=test_suite --report_level=short
