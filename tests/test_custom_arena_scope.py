"""Baseline preservation for the Phoenix/Spider/Dormin visual-only pass."""
from pathlib import Path
import hashlib
import json
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CustomArenaScope(unittest.TestCase):
    def test_previous_assets_and_gameplay_remain_byte_identical(self):
        baseline = json.loads((ROOT / 'tests/fixtures/custom_arena_baseline_assets.json').read_text())
        self.assertEqual(baseline['source_commit'], 'fb21a1a7c9033ea6ea8699171f6901f48cdd622d')
        self.assertGreater(len(baseline['sha256']), 200)
        for relative, expected in baseline['sha256'].items():
            with self.subTest(file=relative):
                self.assertEqual(hashlib.sha256((ROOT / relative).read_bytes()).hexdigest(), expected)


if __name__ == '__main__':
    unittest.main()
