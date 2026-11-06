"""Build-time dependency integrity checks; no network or executable invocation."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("sevenzip", Path(__file__).resolve().parents[1] / "scripts/prepare_native_sevenzip.py")
sevenzip = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sevenzip)


class ProvisionTests(unittest.TestCase):
    def test_corrupt_cached_archive_is_refused_before_output(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(sevenzip.urllib.request, "urlopen") as network:
            root = Path(folder)
            (root / "7z2605-extra.7z").write_bytes(b"wrong cached bytes")
            with self.assertRaisesRegex(ValueError, "digest/size"):
                sevenzip.provision(root, root / "output", "x86_64-pc-windows-msvc", offline=True)
            self.assertFalse((root / "output").exists())
            network.assert_not_called()

    def test_offline_missing_archive_never_downloads(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(sevenzip.urllib.request, "urlopen") as network:
            with self.assertRaisesRegex(ValueError, "Offline cache missing"):
                sevenzip.provision(Path(folder), Path(folder) / "output", "x86_64-unknown-linux-gnu", offline=True)
            network.assert_not_called()


if __name__ == "__main__":
    unittest.main()
