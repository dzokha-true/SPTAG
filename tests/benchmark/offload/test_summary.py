import importlib.util
import pathlib
import unittest

class SummaryTests(unittest.TestCase):
    def test_repeated_legs_report_spread_instead_of_best_run(self):
        path = pathlib.Path(__file__).with_name('summarize.py')
        self.assertTrue(path.is_file(), 'repeat summary tool is missing')
        spec = importlib.util.spec_from_file_location('summary', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        summary = module.summarize(['LEG baseline-r1 wall=2s qps=100 node_net_mb=5 avg_node_cpu_pct=10',
                                    'LEG baseline-r2 wall=1s qps=200 node_net_mb=5 avg_node_cpu_pct=10',
                                    'LEG baseline-r3 wall=4s qps=50 node_net_mb=5 avg_node_cpu_pct=10'])
        self.assertEqual(summary['baseline']['samples'], 3)
        self.assertEqual(summary['baseline']['qps_median'], 100.)
        self.assertEqual(summary['baseline']['qps_min'], 50.)
        self.assertEqual(summary['baseline']['qps_max'], 200.)
        self.assertGreater(summary['baseline']['qps_stdev'], 0.)

if __name__ == '__main__':
    unittest.main()
