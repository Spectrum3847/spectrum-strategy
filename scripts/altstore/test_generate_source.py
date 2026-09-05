#!/usr/bin/env python3
"""Tests for generate_source.py.

Loads the script by file path (it is a standalone tool, not a package) so
the suite runs the same way under `unittest discover` as any other test.
"""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

MODULE_PATH = Path(__file__).resolve().parent / "generate_source.py"
_spec = importlib.util.spec_from_file_location("generate_source", MODULE_PATH)
generate_source = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = generate_source
_spec.loader.exec_module(generate_source)

def make_args(tmp_ipa, **overrides):
    defaults = dict(
        channel="stable",
        out="unused.json",
        ipa=str(tmp_ipa),
        version="1.2.0",
        build_version="42",
        date="2026-08-28T00:00:00Z",
        download_url="https://example.com/app.ipa",
        icon_url="https://example.com/icon.png",
        description="",
        min_os="13.0",
        existing="",
    )
    defaults.update(overrides)
    return SimpleNamespace(**defaults)

class GenerateSourceTest(unittest.TestCase):
    def setUp(self):
        self._tmpdir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self._tmpdir.name)
        self.ipa = self.tmp_path / "app.ipa"
        self.ipa.write_bytes(b"fake ipa contents")

    def tearDown(self):
        self._tmpdir.cleanup()

    def _existing_source(self, versions):
        path = self.tmp_path / "existing.json"
        path.write_text(
            json.dumps({"apps": [{"versions": versions}]}), encoding="utf-8"
        )
        return path

    def test_stable_puts_new_build_first_with_history_in_order(self):
        history = [
            {"version": "1.1.0", "buildVersion": "41"},
            {"version": "1.0.0", "buildVersion": "40"},
        ]
        existing = self._existing_source(history)
        args = make_args(self.ipa, existing=str(existing))

        source = generate_source.build_source(args)
        versions = source["apps"][0]["versions"]

        self.assertEqual(versions[0]["version"], "1.2.0")
        self.assertEqual(
            [v["version"] for v in versions[1:]], ["1.1.0", "1.0.0"]
        )

    def test_history_is_preserved_across_a_run(self):

        args1 = make_args(self.ipa, version="1.0.0", build_version="40")
        source1 = generate_source.build_source(args1)
        out1 = self.tmp_path / "stable.json"
        out1.write_text(json.dumps(source1), encoding="utf-8")

        args2 = make_args(
            self.ipa, version="1.1.0", build_version="41", existing=str(out1)
        )
        source2 = generate_source.build_source(args2)
        versions = source2["apps"][0]["versions"]

        self.assertEqual([v["version"] for v in versions], ["1.1.0", "1.0.0"])

    def test_rerun_of_the_same_build_does_not_duplicate_it(self):
        history = [{"version": "1.0.0", "buildVersion": "40"}]
        existing = self._existing_source(history)
        args = make_args(
            self.ipa, version="1.0.0", build_version="40", existing=str(existing)
        )

        source = generate_source.build_source(args)
        versions = source["apps"][0]["versions"]

        self.assertEqual(len(versions), 1)
        self.assertEqual(versions[0]["version"], "1.0.0")

    def test_nightly_keeps_only_the_new_build_regardless_of_history(self):
        history = [{"version": "1.0.0", "buildVersion": "40"}]
        existing = self._existing_source(history)
        args = make_args(self.ipa, channel="nightly", existing=str(existing))

        source = generate_source.build_source(args)
        versions = source["apps"][0]["versions"]

        self.assertEqual(len(versions), 1)
        self.assertEqual(versions[0]["version"], "1.2.0")

    def test_malformed_existing_source_is_treated_as_no_history(self):
        bad = self.tmp_path / "existing.json"
        bad.write_text("{not valid json", encoding="utf-8")

        self.assertEqual(generate_source.load_existing_versions(str(bad)), [])

        args = make_args(self.ipa, existing=str(bad))
        source = generate_source.build_source(args)
        versions = source["apps"][0]["versions"]

        self.assertEqual(len(versions), 1)
        self.assertEqual(versions[0]["version"], "1.2.0")

    def test_wrong_shaped_existing_source_is_treated_as_no_history(self):

        for name, payload in (
            ("app_not_a_mapping", '{"apps":[null]}'),
            ("versions_not_a_list", '{"apps":[{"versions":null}]}'),
            ("versions_entry_not_a_mapping", '{"apps":[{"versions":[null]}]}'),
        ):
            with self.subTest(name):
                bad = self.tmp_path / f"{name}.json"
                bad.write_text(payload, encoding="utf-8")

                self.assertEqual(
                    generate_source.load_existing_versions(str(bad)), []
                )

    def test_missing_existing_source_is_treated_as_no_history(self):
        missing = str(self.tmp_path / "does-not-exist.json")

        self.assertEqual(generate_source.load_existing_versions(missing), [])

    def test_retired_release_host_is_repointed_in_history(self):
        history = [
            {
                "version": "1.0.0",
                "buildVersion": "40",
                "downloadURL": "https://github.com/"
                f"{generate_source.RETIRED_RELEASE_HOST}/releases/download/v1.0.0/app.ipa",
            }
        ]
        existing = self._existing_source(history)

        loaded = generate_source.load_existing_versions(str(existing))

        self.assertIn(generate_source.CURRENT_RELEASE_HOST, loaded[0]["downloadURL"])
        self.assertNotIn(
            generate_source.RETIRED_RELEASE_HOST, loaded[0]["downloadURL"]
        )

if __name__ == "__main__":
    unittest.main()
