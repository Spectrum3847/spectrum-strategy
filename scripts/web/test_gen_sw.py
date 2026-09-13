#!/usr/bin/env python3
"""Unit tests for scripts/web/gen_sw.py."""

import tempfile
import unittest
from pathlib import Path

from scripts.web import gen_sw

TEMPLATE = (
    "const CACHE = 'spectrum-strategy-{{BUILD_ID}}';\n"
    "const SHELL = [\n"
    "  './',\n"
    "  'index.html',\n"
    "  'manifest.json',\n"
    "];\n"
)

def make_build_dir(root, bootstrap=b"bootstrap", main_js=b"main", manifest=b"{}"):
    build = Path(root) / "web"
    (build / "assets").mkdir(parents=True)
    (build / "flutter_bootstrap.js").write_bytes(bootstrap)
    (build / "main.dart.js").write_bytes(main_js)
    (build / "index.html").write_bytes(b"<html></html>")
    (build / "manifest.json").write_bytes(manifest)
    (build / "assets" / "AssetManifest.bin.json").write_bytes(b"[]")
    return build

def write_template(root, text=TEMPLATE):
    path = Path(root) / "sw.template.js"
    path.write_text(text)
    return path

class BuildIdTest(unittest.TestCase):
    def test_same_bundle_gives_the_same_id(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            first = gen_sw.build_id(make_build_dir(a), TEMPLATE)
            second = gen_sw.build_id(make_build_dir(b), TEMPLATE)
            self.assertEqual(first, second)

    def test_a_changed_bundle_gives_a_different_id(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            first = gen_sw.build_id(make_build_dir(a, main_js=b"main"), TEMPLATE)
            second = gen_sw.build_id(make_build_dir(b, main_js=b"main-v2"), TEMPLATE)
            self.assertNotEqual(first, second)

    def test_a_bundle_with_none_of_the_hashed_files_is_an_error(self):
        with tempfile.TemporaryDirectory() as root:
            empty = Path(root) / "web"
            empty.mkdir()
            with self.assertRaises(FileNotFoundError):
                gen_sw.build_id(empty, TEMPLATE)

class HashedFilesTest(unittest.TestCase):
    """The hashed set is read from the template, so the two cannot drift.

    A hand-maintained second list let a change to manifest.json alone leave the
    build id, and therefore the cache name, identical. The browser then saw no
    new worker and kept serving the copy it already had.
    """

    EXPECTED_SHELL = (
        "./",
        "index.html",
        "manifest.json",
        "favicon.png",
        "flutter_bootstrap.js",
        "offline-check.html",
        "assets/AssetManifest.bin.json",
        "assets/FontManifest.json",
    )

    def test_the_template_shell_is_exactly_what_we_expect(self):
        shell = gen_sw.shell_files(Path("web/sw.template.js").read_text())
        self.assertEqual(shell, self.EXPECTED_SHELL)

    def test_every_precached_file_is_hashed(self):
        hashed = gen_sw.hashed_files(Path("web/sw.template.js").read_text())
        for name in self.EXPECTED_SHELL:
            self.assertIn(name, hashed, f"{name} is precached but not hashed")

    def test_a_dropped_entry_would_be_caught(self):

        shell = gen_sw.shell_files(
            "const SHELL = [\n  'index.html',\n  \"manifest.json\",\n];"
        )
        self.assertEqual(shell, ("index.html", "manifest.json"))

    def test_an_unreadable_entry_raises_rather_than_dropping(self):
        for bad in (
            "const SHELL = [\n  index.html,\n];",
            "const SHELL = [\n  'a.js' + x,\n];",
        ):
            with self.assertRaises(ValueError):
                gen_sw.shell_files(bad)

    def test_two_shell_arrays_raise(self):
        with self.assertRaises(ValueError):
            gen_sw.shell_files("const SHELL = [\n];\nconst SHELL = [\n];")

    def test_a_commented_out_entry_is_not_hashed(self):
        shell = gen_sw.shell_files(
            "const SHELL = [\n  'a.js',\n  // 'gone.js',\n];"
        )
        self.assertEqual(shell, ("a.js",))

    def test_the_compiled_bundle_is_hashed(self):
        template = Path("web/sw.template.js").read_text()
        hashed = gen_sw.hashed_files(template)
        for name in gen_sw.ENGINE_FILES:
            self.assertIn(name, hashed)

    def test_a_template_without_a_shell_list_is_an_error(self):
        with self.assertRaises(ValueError):
            gen_sw.shell_files("const CACHE = 'x-{{BUILD_ID}}';")

    def test_a_manifest_only_change_rotates_the_id(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            first = gen_sw.build_id(make_build_dir(a, manifest=b'{"a":1}'), TEMPLATE)
            second = gen_sw.build_id(make_build_dir(b, manifest=b'{"a":2}'), TEMPLATE)
            self.assertNotEqual(first, second)

class GenerateTest(unittest.TestCase):
    def test_writes_sw_js_with_the_token_substituted(self):
        with tempfile.TemporaryDirectory() as root:
            build = make_build_dir(root)
            template = write_template(root)

            written = gen_sw.generate(build, template)

            self.assertEqual(written, build / "sw.js")
            worker = written.read_text()
            self.assertNotIn("{{", worker)
            self.assertIn(
                f"spectrum-strategy-{gen_sw.build_id(build, template.read_text())}",
                worker,
            )

    def test_deletes_flutters_self_unregistering_worker(self):
        with tempfile.TemporaryDirectory() as root:
            build = make_build_dir(root)
            tombstone = build / gen_sw.TOMBSTONE
            tombstone.write_text("self.registration.unregister()")

            gen_sw.generate(build, write_template(root))

            self.assertFalse(tombstone.exists())

    def test_a_missing_tombstone_is_not_an_error(self):
        with tempfile.TemporaryDirectory() as root:
            build = make_build_dir(root)
            gen_sw.generate(build, write_template(root))
            self.assertTrue((build / "sw.js").exists())

    def test_a_template_without_the_token_is_an_error(self):
        with tempfile.TemporaryDirectory() as root:
            build = make_build_dir(root)
            template = write_template(root, "const CACHE = 'fixed';\n")
            with self.assertRaises(ValueError):
                gen_sw.generate(build, template)

    def test_a_template_with_a_leftover_token_is_an_error(self):
        with tempfile.TemporaryDirectory() as root:
            build = make_build_dir(root)
            template = write_template(root, TEMPLATE + "// {{SOMETHING_ELSE}}\n")
            with self.assertRaises(ValueError):
                gen_sw.generate(build, template)

    def test_a_missing_build_dir_is_an_error(self):
        with tempfile.TemporaryDirectory() as root:
            template = write_template(root)
            with self.assertRaises(FileNotFoundError):
                gen_sw.generate(Path(root) / "nope", template)

class RealTemplateTest(unittest.TestCase):
    """The checked-in template must stay substitutable by this script."""

    def test_the_repo_template_has_exactly_one_kind_of_token(self):
        template = Path("web/sw.template.js").read_text()
        self.assertIn(gen_sw.TEMPLATE_TOKEN, template)
        self.assertNotIn(
            "{{",
            template.replace(gen_sw.TEMPLATE_TOKEN, ""),
            "the template carries a token gen_sw.py does not substitute",
        )

class BootstrapTest(unittest.TestCase):
    """web/flutter_bootstrap.js must not name a placeholder twice.

    `flutter build web` replaces every occurrence of a placeholder, a comment
    included. The loader it substitutes is multi-line, so a placeholder named
    inside a `//` comment leaves the rest of the loader running as stray code
    and the app never boots. This caught exactly that.
    """

    PLACEHOLDERS = ("{{flutter_js}}", "{{flutter_build_config}}")

    def test_each_placeholder_appears_exactly_once(self):
        bootstrap = Path("web/flutter_bootstrap.js").read_text()
        for placeholder in self.PLACEHOLDERS:
            self.assertEqual(
                bootstrap.count(placeholder),
                1,
                f"{placeholder} must appear once, never in a comment",
            )

    def test_no_other_placeholder_is_left_unexpanded(self):
        bootstrap = Path("web/flutter_bootstrap.js").read_text()
        for placeholder in self.PLACEHOLDERS:
            bootstrap = bootstrap.replace(placeholder, "")
        self.assertNotIn("{{", bootstrap)

    def test_the_deprecated_service_worker_is_not_registered(self):
        bootstrap = Path("web/flutter_bootstrap.js").read_text()
        self.assertNotIn("serviceWorkerSettings:", bootstrap)

if __name__ == "__main__":
    unittest.main()
