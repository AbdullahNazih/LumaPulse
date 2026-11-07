import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('report', Path(__file__).resolve().parents[1] / 'scripts/download-report.py')
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)

class DownloadReportTests(unittest.TestCase):
    def make(self, assets):
        return {'repository': report.REPO, 'observed_at': 'test', 'assets': assets}

    def test_counts_packages_only_and_baseline(self):
        releases = [{'tag_name': 'v1', 'assets': [{'id': 1, 'name': 'LumaPulse-v1.zip', 'download_count': 12}, {'id': 2, 'name': 'LumaPulse-v1.zip.sha256', 'download_count': 50}]}]
        result = report.compare(report.snapshot(releases, 'now'), None)
        self.assertEqual(result['total'], 12)
        self.assertIsNone(result['increase'])

    def test_replaced_asset_is_not_negative(self):
        before = self.make({'1': {'name': 'old.zip', 'count': 100}})
        after = self.make({'2': {'name': 'new.zip', 'count': 3}})
        result = report.compare(after, before)
        self.assertEqual(result['increase'], 3)
        self.assertEqual(result['removed'], ['old.zip'])

    def test_counter_reset_and_increment(self):
        before = self.make({'1': {'name': 'a', 'count': 10}, '2': {'name': 'b', 'count': 5}})
        after = self.make({'1': {'name': 'a', 'count': 2}, '2': {'name': 'b', 'count': 8}})
        result = report.compare(after, before)
        self.assertEqual(result['increase'], 3)
        self.assertEqual(result['reset'], ['a'])

    def test_snapshot_is_atomic_and_private(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'downloads.json'
            report.write_snapshot(path, self.make({}))
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(len(list(Path(directory).iterdir())), 1)

if __name__ == '__main__':
    unittest.main()
