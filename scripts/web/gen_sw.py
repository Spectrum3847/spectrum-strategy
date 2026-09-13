#!/usr/bin/env python3
"""gen_sw.py -- write build/web/sw.js from web/sw.template.js.

`flutter build web` does not produce a usable service worker any more: as of
Flutter 3.47 the generated `flutter_service_worker.js` is a tombstone whose
only job is to unregister itself, so an offline-capable web build has to ship
its own. This substitutes a build id into the template and drops the result
next to the bundle it caches.

The build id is a content hash of the files that define a build, so it changes
exactly when the bundle does. The service worker names its cache after it,
which is what makes a deploy replace the previous build's cache instead of
mixing the two, and what makes the browser see a new worker at all.

`flutter_service_worker.js` is deleted, because it claims the same "/" scope
and registering it would evict the worker written here.

Usage: gen_sw.py [build_dir] [--template PATH]
Exit 0 clean, exit 1 with a message otherwise. No network.
"""

import argparse
import hashlib
import re
import sys
from pathlib import Path

TEMPLATE_TOKEN = "{{BUILD_ID}}"

ENGINE_FILES = (
    "flutter_bootstrap.js",
    "main.dart.js",
    "main.dart.wasm",
    "main.dart.mjs",
)

SHELL_PATTERN = re.compile(r"const SHELL = \[(.*?)\];", re.DOTALL)

SHELL_ENTRY_PATTERN = re.compile(r"^\s*(?:'([^']+)'|\"([^\"]+)\")\s*,?\s*$")

TOMBSTONE = "flutter_service_worker.js"

def shell_files(template):
    """The paths listed in the template's SHELL array, in order.

    Strict on purpose. Every non-blank, non-comment line in the array has to
    parse as one quoted path, and a second SHELL array is an error, because the
    failure mode of a lenient parser here is not a crash: it is a shorter list,
    a build id that stops changing, and a browser pinned to a stale cache.
    """
    matches = SHELL_PATTERN.findall(template)
    if not matches:
        raise ValueError("the template has no `const SHELL = [...]` to read")
    if len(matches) > 1:
        raise ValueError(
            f"the template has {len(matches)} `const SHELL = [...]` arrays; "
            "there must be exactly one"
        )
    paths = []
    for line in matches[0].splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        entry = SHELL_ENTRY_PATTERN.match(line)
        if entry is None:
            raise ValueError(
                f"cannot read {stripped!r} as a SHELL entry; each line must be "
                "one quoted path"
            )
        paths.append(entry.group(1) or entry.group(2))
    return tuple(paths)

def hashed_files(template):
    """Every path whose contents must rotate the build id.

    The worker's precache list plus the compiled bundle, de-duplicated and
    ordered so the hash is reproducible.
    """
    names = list(ENGINE_FILES)
    for name in shell_files(template):
        if name not in names:
            names.append(name)
    return tuple(names)

def build_id(build_dir, template):
    """A short, stable content hash of the files that define this build."""
    digest = hashlib.sha256()
    names = hashed_files(template)
    hashed_any = False
    for name in names:
        path = Path(build_dir) / name
        if not path.is_file():

            continue
        hashed_any = True

        digest.update(name.encode())
        digest.update(path.read_bytes())
    if not hashed_any:
        raise FileNotFoundError(
            f"{build_dir} holds none of {', '.join(names)}; "
            "run `flutter build web` first"
        )
    return digest.hexdigest()[:16]

def generate(build_dir, template_path):
    build_dir = Path(build_dir)
    template_path = Path(template_path)
    if not build_dir.is_dir():
        raise FileNotFoundError(f"{build_dir} does not exist")
    template = template_path.read_text()
    if TEMPLATE_TOKEN not in template:
        raise ValueError(f"{template_path} has no {TEMPLATE_TOKEN} to substitute")

    worker = template.replace(TEMPLATE_TOKEN, build_id(build_dir, template))
    if "{{" in worker:
        raise ValueError(f"{template_path} left an unsubstituted token behind")

    (build_dir / "sw.js").write_text(worker)
    (build_dir / TOMBSTONE).unlink(missing_ok=True)
    return build_dir / "sw.js"

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build_dir", nargs="?", default="build/web")
    parser.add_argument("--template", default="web/sw.template.js")
    args = parser.parse_args()
    try:
        written = generate(args.build_dir, args.template)
    except (FileNotFoundError, ValueError) as error:
        print(f"gen_sw.py: {error}", file=sys.stderr)
        return 1
    print(f"gen_sw.py: wrote {written}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
