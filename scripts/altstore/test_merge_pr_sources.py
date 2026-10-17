#!/usr/bin/env python3
"""Tests for merge_pr_sources.py, loaded by file path like its sibling suite."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent

def _load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module

merge = _load("merge_pr_sources")
generate_source = _load("generate_source")

class MergePrSourcesTest(unittest.TestCase):
    def setUp(self):
        self._tmpdir = tempfile.TemporaryDirectory()
        self.root = Path(self._tmpdir.name)
        self.ipa = self.root / "app.ipa"
        self.ipa.write_bytes(b"fake ipa")

    def tearDown(self):
        self._tmpdir.cleanup()

    def _entry(self, pr, date="2026-09-10T00:00:00Z", folder=None):
        args = generate_source.parse_args(
            [
                "--channel", "pr", "--pr", str(pr),
                "--out", "unused", "--ipa", str(self.ipa),
                "--version", "0.0.0", "--build-version", f"{pr}.1",
                "--date", date,
                "--download-url", f"https://example.com/pr-{pr}.ipa",
                "--icon-url", "https://example.com/icon.png",
            ]
        )
        source = generate_source.build_source(args)
        path = self.root / (folder or "flat") / f"source-pr{pr}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(source), encoding="utf-8")
        return source

    def test_newest_pr_first_with_distinct_bundle_ids(self):
        self._entry(1713)
        self._entry(1720)
        self._entry(99)

        apps = merge.load_apps(self.root)

        self.assertEqual(
            [a["bundleIdentifier"] for a in apps],
            [
                "org.spectrum3847.spectrumstrategy.pr1720",
                "org.spectrum3847.spectrumstrategy.pr1713",
                "org.spectrum3847.spectrumstrategy.pr99",
            ],
        )
        self.assertEqual(apps[1]["name"], "Spectrum Strategy PR 1713")

    def test_malformed_and_foreign_entries_are_skipped(self):
        self._entry(1713)
        (self.root / "flat" / "source-pr5.json").write_text("{nope", encoding="utf-8")
        nightly = self.root / "nightly" / "source.json"
        nightly.parent.mkdir()
        nightly.write_text(
            json.dumps({"apps": [{"bundleIdentifier": "org.x.app", "versions": [{}]}]}),
            encoding="utf-8",
        )

        apps = merge.load_apps(self.root)

        self.assertEqual(len(apps), 1)
        self.assertEqual(merge.pr_number(apps[0]), 1713)

    def test_duplicate_pr_keeps_the_newer_build(self):
        self._entry(1713, date="2026-09-01T00:00:00Z", folder="a")
        self._entry(1713, date="2026-09-09T00:00:00Z", folder="b")

        apps = merge.load_apps(self.root)

        self.assertEqual(len(apps), 1)
        self.assertEqual(apps[0]["versions"][0]["date"], "2026-09-09T00:00:00Z")

    def test_empty_directory_yields_a_valid_empty_source(self):
        source = merge.build_source(merge.load_apps(self.root), "https://i/icon.png")

        self.assertEqual(source["apps"], [])
        self.assertEqual(source["name"], merge.SOURCE_NAME)

    def test_main_writes_the_file(self):
        self._entry(1713)
        out = self.root / "pr.json"

        merge.main(["--entries", str(self.root), "--out", str(out),
                    "--icon-url", "https://i/icon.png"])

        written = json.loads(out.read_text(encoding="utf-8"))
        self.assertEqual(len(written["apps"]), 1)
        self.assertEqual(written["iconURL"], "https://i/icon.png")

if __name__ == "__main__":
    unittest.main()
