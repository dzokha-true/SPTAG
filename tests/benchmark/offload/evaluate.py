"""Exact exhaustive squared-L2 recall for seeded float32 DEFAULT files.

NumPy float64 arithmetic is an independent oracle; no SPTAG index is used.
Queries are processed in batches of 16 to bound the temporary score matrix.
This measures accuracy only; it never times search or estimates speedup.
"""
import argparse
import hashlib
import json
import pathlib
import struct
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / 'integration' / 'offload'))
from compare import read_results, REL_TOL


def read_vectors(path):
    raw = pathlib.Path(path).read_bytes()
    if len(raw) < 8:
        raise ValueError(f'{path}: incomplete vector header')
    count, dim = struct.unpack_from('<ii', raw)
    if count <= 0 or dim <= 0 or len(raw) != 8 + count * dim * 4:
        raise ValueError(f'{path}: invalid vector header/length (possibly an LFS pointer)')
    data = np.frombuffer(raw, dtype='<f4', offset=8).reshape(count, dim).astype(np.float64)
    if not np.isfinite(data).all():
        raise ValueError(f'{path}: non-finite vectors')
    return data, hashlib.sha256(raw).hexdigest()


def evaluate(base, queries, results):
    k = len(results[0][0])
    if k > len(base) or any(len(rows) != len(queries) or len(rows[0]) != k for rows in results):
        raise ValueError('result Q/K does not match inputs')
    if base.shape[1] != queries.shape[1]:
        raise ValueError('base/query dimensions differ')
    scores = [[] for _ in results]
    mismatch_counts = [0 for _ in results]
    norms = np.einsum('ij,ij->i', base, base)
    for start in range(0, len(queries), 16):
        block = queries[start:start+16]
        distances = norms[None, :] + np.einsum('ij,ij->i', block, block)[:, None] - 2 * block @ base.T
        np.maximum(distances, 0., out=distances)
        for offset, dists in enumerate(distances):
            qi = start + offset
            # Deterministic VID tie break. Only partition, not sort, the full population.
            boundary = np.partition(dists, k - 1)[k - 1]
            candidates = np.flatnonzero(dists <= boundary)
            truth = set(candidates[np.lexsort((candidates, dists[candidates]))[:k]].tolist())
            for ri, rows in enumerate(results):
                ids = [vid for vid, _ in rows[qi]]
                if any(vid >= len(base) for vid in ids):
                    raise ValueError(f'result {ri} query {qi}: VID outside base vectors')
                scores[ri].append(len(truth.intersection(ids)) / k)
                for vid, measured in rows[qi]:
                    expected = dists[vid]
                    if abs(expected-measured) > REL_TOL * max(1., abs(expected), abs(measured)):
                        mismatch_counts[ri] += 1
    return [dict(recall_at_k=float(np.mean(values)), worst_recall_at_k=min(values),
                 worst_query=int(np.argmin(values)), queries_below_0_99=sum(x < .99 for x in values),
                 distance_mismatches=mismatch_counts[i]) for i, values in enumerate(scores)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base')
    parser.add_argument('queries')
    parser.add_argument('results', nargs='+')
    args = parser.parse_args()
    base, base_sha = read_vectors(args.base)
    queries, query_sha = read_vectors(args.queries)
    results = [read_results(path) for path in args.results]
    metrics = evaluate(base, queries, results)
    for path, item in zip(args.results, metrics):
        item['file'] = path
        item['sha256'] = hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()
    print(json.dumps(dict(metric='exact squared L2; float64 oracle; ties ordered by VID',
                         vectors=len(base), queries=len(queries), dimension=base.shape[1],
                         k=len(results[0][0]), base_sha256=base_sha, query_sha256=query_sha,
                         results=metrics), indent=2))


if __name__ == '__main__':
    main()
