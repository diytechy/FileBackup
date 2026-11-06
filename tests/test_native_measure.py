"""The performance sampler must count concurrent children and stop runaway probes."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('measure_native', Path(__file__).resolve().parents[1]/'scripts/measure_native.py')
sampler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sampler)


class MeasurementTests(unittest.TestCase):
    def test_simultaneous_children_and_refusal_to_overwrite(self):
        with tempfile.TemporaryDirectory() as root:
            output = Path(root)/'tree.json'
            child = 'import time; data=bytearray(24*1024*1024); time.sleep(1)'
            parent = f'import subprocess,sys; children=[subprocess.Popen([sys.executable,"-c",{child!r}]) for _ in range(2)]; [p.wait() for p in children]'
            result = sampler.measure([sys.executable, '-c', parent], output, 'tree')
            self.assertEqual(result['exit_code'], 0)
            self.assertFalse(result['measurement_errors'])
            self.assertGreaterEqual(result['max_simultaneous_processes'], 3)
            self.assertGreater(result['peak_rss_bytes'], 48*1024*1024)
            self.assertEqual(json.loads(output.read_text())['samples'], result['samples'])
            with self.assertRaises(FileExistsError):
                sampler.measure([sys.executable, '-c', 'pass'], output, 'refused')

    def test_elapsed_limit_stops_operation(self):
        with tempfile.TemporaryDirectory() as root:
            result = sampler.measure([sys.executable, '-c', 'import time; time.sleep(30)'], Path(root)/'limit.json', 'limit', seconds=0.2)
            self.assertEqual(result['stopped'], 'elapsed_limit')
            self.assertNotEqual(result['exit_code'], 0)
            self.assertLess(result['elapsed_seconds'], 5)


if __name__ == '__main__':
    unittest.main()
