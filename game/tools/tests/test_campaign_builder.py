"""Authoring must be reproducible and importing it must never publish content."""
import contextlib
import io
import json
from pathlib import Path
import runpy
import sys
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1]


class CampaignBuilderChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(TOOLS))
        cls.output = io.StringIO()
        try:
            with contextlib.redirect_stdout(cls.output), patch.object(
                    Path, "write_text", side_effect=AssertionError("write during import")):
                cls.module = runpy.run_path(str(TOOLS / "build_campaign_v2.py"))
        finally:
            sys.path.pop(0)

    def test_import_is_silent(self):
        self.assertEqual(self.output.getvalue(), "")

    def test_generated_campaign_matches_delivery(self):
        delivered = json.loads((TOOLS.parent / "data/campaign/campaign_v2.json").read_text(
            encoding="utf-8"))
        self.assertEqual(self.module["result"], delivered)


if __name__ == "__main__":
    unittest.main()
