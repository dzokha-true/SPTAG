"""EC528: seeded synthetic dataset in SPTAG DEFAULT binary format
(int32 count, int32 dim, float32 row-major)."""
import random
import struct
import sys

SEED = 528


def write_default_bin(path: str, count: int, dim: int, seed: int) -> None:
    rng = random.Random(seed)
    with open(path, "wb") as f:
        f.write(struct.pack("<ii", count, dim))
        for _ in range(count):
            row = [rng.uniform(-1.0, 1.0) for _ in range(dim)]
            f.write(struct.pack(f"<{dim}f", *row))


if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 5000
    queries = int(sys.argv[3]) if len(sys.argv) > 3 else 100
    dim = int(sys.argv[4]) if len(sys.argv) > 4 else 64

    write_default_bin(f"{out_dir}/base.bin", count, dim, SEED)
    write_default_bin(f"{out_dir}/query.bin", queries, dim, SEED + 1)
    print(f"generated {count}x{dim} base + {queries} queries in {out_dir}")
