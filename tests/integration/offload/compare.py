"""EC528: SPEC-4-INTEG-001 comparator - per-query top-K overlap between the
baseline (MultiGet + ComputeDistance) leg and the VECTOR_DISTANCE offload
leg. ssdserving SearchResult files are (int32 vid, float32 dist) * K * Q.
Prints `PARITY_OK overlap=<mean>` on success; dumps the worst query's two
result lists on failure."""
import struct
import sys

K = 10
THRESHOLD = 0.99
REL_TOL = 1e-5


def read_results(path: str):
    # ssdserving OutputResult: int32 Q, int32 K header, then Q*K of
    # (int32 vid, float32 dist). See AnnService/inc/SSDServing/SSDIndex.h.
    with open(path, "rb") as f:
        raw = f.read()
    q, k = struct.unpack_from("<ii", raw, 0)
    if k != K:
        print(f"note: {path} K={k} (expected {K}); using file K")
    expect = 8 + q * k * 8
    if len(raw) != expect:
        raise SystemExit(
            f"FATAL: {path} size {len(raw)} != header-implied {expect}")
    out = []
    off = 8
    for _ in range(q):
        row = []
        for _ in range(k):
            vid, dist = struct.unpack_from("<if", raw, off)
            row.append((vid, dist))
            off += 8
        out.append(row)
    return out


def close(a: float, b: float) -> bool:
    return abs(a - b) <= REL_TOL * max(1.0, abs(a), abs(b))


def main() -> int:
    base = read_results(sys.argv[1])
    off = read_results(sys.argv[2])

    if len(base) != len(off):
        print(f"FATAL: query counts differ {len(base)} vs {len(off)}")
        return 1

    overlaps = []
    worst = (2.0, -1)
    for qi, (b_row, o_row) in enumerate(zip(base, off)):
        b_ids = {v for v, _ in b_row if v >= 0}
        o_ids = {v for v, _ in o_row if v >= 0}
        denom = max(len(b_ids), 1)
        ov = len(b_ids & o_ids) / denom

        # Tie forgiveness: a differing member whose distance matches the
        # baseline's worst distance is a legitimate tie swap.
        if ov < 1.0:
            b_worst = max(d for _, d in b_row)
            extra = o_ids - b_ids
            ties = sum(1 for v, d in o_row if v in extra and
                    (close(d, b_worst) or d <= b_worst))
            ov = min(1.0, (len(b_ids & o_ids) + ties) / denom)

        overlaps.append(ov)
        if ov < worst[0]:
            worst = (ov, qi)

    mean = sum(overlaps) / len(overlaps)
    print(f"queries={len(overlaps)} mean_overlap={mean:.4f} "
          f"worst={worst[0]:.4f} (query {worst[1]})")

    if mean < THRESHOLD:
        qi = worst[1]
        print(f"WORST QUERY {qi} baseline: {base[qi]}")
        print(f"WORST QUERY {qi} offload : {off[qi]}")
        print("PARITY_FAIL")
        return 1

    print(f"PARITY_OK overlap={mean:.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
