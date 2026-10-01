"""EC528: result parity, distinct from exact ground-truth recall.

ssdserving files contain int32 Q,K then Q*K (int32 VID,float32 distance).
The mean 0.99 gate permits outliers; always print the worst query. Boundary
credit requires both the displaced baseline hit and replacement to be tied.
"""
import math
import struct
import sys

THRESHOLD = 0.99
REL_TOL = 1e-5


def read_results(path):
    with open(path, 'rb') as f:
        raw = f.read()
    if len(raw) < 8:
        raise ValueError(f'{path}: incomplete result header')
    q, k = struct.unpack_from('<ii', raw)
    if q <= 0 or k <= 0 or len(raw) != 8 + q * k * 8:
        raise ValueError(f'{path}: invalid dimensions or size (Q={q}, K={k})')
    out = []
    for qi in range(q):
        row = [struct.unpack_from('<if', raw, 8 + (qi*k+i)*8) for i in range(k)]
        if any(v < 0 or not math.isfinite(d) for v, d in row):
            raise ValueError(f'{path}: query {qi} has missing IDs or non-finite distances')
        if len({v for v, _ in row}) != k:
            raise ValueError(f'{path}: query {qi} has duplicate IDs')
        out.append(row)
    return out


def close(a, b):
    return abs(a - b) <= REL_TOL * max(1.0, abs(a), abs(b))


def compare(base, off):
    if len(base) != len(off) or len(base[0]) != len(off[0]):
        raise ValueError('query counts or K differ')
    strict, adjusted = [], []
    mismatches = []
    for qi, (b_row, o_row) in enumerate(zip(base, off)):
        b, o = dict(b_row), dict(o_row)
        common = b.keys() & o.keys()
        mismatches.extend((qi, v, b[v], o[v]) for v in sorted(common) if not close(b[v], o[v]))
        boundary = max(b.values())
        missing_ties = sum(close(b[v], boundary) for v in b.keys() - o.keys())
        extra_ties = sum(close(o[v], boundary) for v in o.keys() - b.keys())
        strict.append(len(common) / len(b))
        adjusted.append((len(common) + min(missing_ties, extra_ties)) / len(b))
    return strict, adjusted, mismatches


def main():
    if len(sys.argv) != 3:
        print('usage: compare.py BASELINE RESULTS', file=sys.stderr)
        return 2
    try:
        base, off = map(read_results, sys.argv[1:])
        strict, adjusted, mismatches = compare(base, off)
    except ValueError as exc:
        print(f'FATAL: {exc}', file=sys.stderr)
        return 1
    mean = sum(adjusted) / len(adjusted)
    worst = min(range(len(adjusted)), key=lambda qi: (adjusted[qi], strict[qi]))
    print(f'queries={len(base)} strict_mean_overlap={sum(strict)/len(strict):.4f} '
          f'mean_overlap={mean:.4f} worst={adjusted[worst]:.4f} (query {worst}) '
          f'queries_below_0.99={sum(x < THRESHOLD for x in adjusted)} '
          f'distance_mismatches={len(mismatches)}')
    print(f'WORST QUERY {worst} baseline: {base[worst]}')
    print(f'WORST QUERY {worst} offload : {off[worst]}')
    for qi, vid, b, o in mismatches[:10]:
        print(f'DISTANCE_MISMATCH query={qi} vid={vid} baseline={b} offload={o}')
    if mean < THRESHOLD or mismatches:
        print('PARITY_FAIL')
        return 1
    print(f'PARITY_OK overlap={mean:.4f}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
