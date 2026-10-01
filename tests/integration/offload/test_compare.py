"""Regression tests for the result-file parity gate (no cluster required)."""
import pathlib
import struct
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name('compare.py')

class CompareTests(unittest.TestCase):
    def compare(self, baseline, offload):
        with tempfile.TemporaryDirectory() as tmp:
            paths = [pathlib.Path(tmp) / name for name in ('base.bin', 'off.bin')]
            for path, rows in zip(paths, (baseline, offload)):
                path.write_bytes(struct.pack('<ii', len(rows), len(rows[0])) +
                    b''.join(struct.pack('<if', *item) for row in rows for item in row))
            return subprocess.run([sys.executable, str(SCRIPT), *map(str, paths)],
                                  capture_output=True, text=True)

    def test_closer_different_candidates_are_not_boundary_ties(self):
        result = self.compare([[(1, 10.), (2, 20.)]], [[(3, 1.), (4, 2.)]])
        self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_matching_ids_with_corrupt_distances_fail(self):
        result = self.compare([[(1, 10.), (2, 20.)]], [[(1, 100.), (2, 200.)]])
        self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_duplicate_ids_cannot_shrink_denominator(self):
        result = self.compare([[(1, 10.), (1, 10.)]], [[(1, 10.), (1, 10.)]])
        self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_real_boundary_tie_passes_but_reports_strict_overlap(self):
        result = self.compare([[(1, 10.), (2, 20.)]], [[(1, 10.), (3, 20.)]])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('strict_mean_overlap=0.5000', result.stdout)
        self.assertIn('WORST QUERY 0', result.stdout)

    def test_nan_distance_fails(self):
        result = self.compare([[(1, 10.)]], [[(1, float('nan'))]])
        self.assertNotEqual(result.returncode, 0, result.stdout)

if __name__ == '__main__':
    unittest.main()
