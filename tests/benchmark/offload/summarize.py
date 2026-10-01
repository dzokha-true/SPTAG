"""Aggregate repeated harness observations without selecting the best run."""
import collections
import json
import pathlib
import re
import statistics
import sys


def summarize(lines):
    groups = collections.defaultdict(list)
    for line in lines:
        match = re.match(r'LEG (.+)-r\d+ wall=([\d.]+)s qps=([\d.]+)', line)
        if match:
            groups[match[1]].append(float(match[3]))
    if not groups:
        raise ValueError('no repeated LEG records found')
    return {name: dict(samples=len(qps), qps_median=statistics.median(qps),
                       qps_min=min(qps), qps_max=max(qps),
                       qps_stdev=statistics.stdev(qps) if len(qps) > 1 else None)
            for name, qps in groups.items()}


if __name__ == '__main__':
    print(json.dumps(summarize(pathlib.Path(sys.argv[1]).read_text().splitlines()), indent=2))
