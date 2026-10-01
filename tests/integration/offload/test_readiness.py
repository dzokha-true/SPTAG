import importlib.util
import pathlib
import unittest

class ReadinessTests(unittest.TestCase):
    def test_listening_before_partition_assignment_is_not_ready(self):
        path = pathlib.Path(__file__).with_name('wait_ready.py')
        self.assertTrue(path.is_file(), 'functional cluster readiness is missing')
        spec = importlib.util.spec_from_file_location('ready', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertFalse(module.ready('partition-generation\t-1\nstatistics\tcluster_size=1;foo=bar\n', 1))
        self.assertFalse(module.ready('partition-generation\t0\nstatistics\tcluster_size=1\n', 3))
        self.assertFalse(module.ready('partition-generation\t0\n', 1))
        self.assertTrue(module.ready('partition-generation\t0\nstatistics\tcluster_size=3;foo=bar\n', 3))

if __name__ == '__main__':
    unittest.main()
