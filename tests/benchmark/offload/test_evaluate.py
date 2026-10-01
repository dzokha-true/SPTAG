"""Tiny exhaustive fixtures for the independent L2 recall evaluator."""
import json
import pathlib
import struct
import subprocess
import sys
import tempfile
import unittest

class RecallTests(unittest.TestCase):
    def evaluate(self, result_rows):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            for name, rows in [('base.bin', [[0., 0.], [1., 0.], [3., 0.]]),
                               ('query.bin', [[0., 0.], [3., 0.]])]:
                (root / name).write_bytes(struct.pack('<ii', len(rows), 2) +
                    b''.join(struct.pack('<2f', *row) for row in rows))
            (root / 'results.bin').write_bytes(struct.pack('<ii', 2, 1) +
                    b''.join(struct.pack('<if', *row) for row in result_rows))
            return subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name('evaluate.py')),
                str(root / 'base.bin'), str(root / 'query.bin'), str(root / 'results.bin')],
                text=True, capture_output=True)

    def test_exact_hits_have_perfect_recall_and_valid_distances(self):
        run = self.evaluate([(0, 0.), (2, 0.)])
        self.assertEqual(run.returncode, 0, run.stderr)
        data = json.loads(run.stdout)['results'][0]
        self.assertEqual(data['recall_at_k'], 1.)
        self.assertEqual(data['distance_mismatches'], 0)

    def test_identical_ann_outputs_can_have_poor_exact_recall(self):
        run = self.evaluate([(1, 1.), (1, 4.)])
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(json.loads(run.stdout)['results'][0]['recall_at_k'], 0.)

    def test_correct_ids_do_not_hide_wrong_distances(self):
        run = self.evaluate([(0, 15.), (2, 15.)])
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(json.loads(run.stdout)['results'][0]['distance_mismatches'], 2)

if __name__ == '__main__':
    unittest.main()
