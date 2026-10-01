#!/usr/bin/env python3
"""Merge per-PR AltStore sources into the one source testers subscribe to.

Each pull request test build publishes a single-app source (generate_source.py
--channel pr) as `source-pr<number>.json` on the rolling `pr-builds` release
on the public mirror. The mirror's pr-build workflow downloads every such
file, hands the directory to this script, and deploys the result as `pr.json`. Because every
PR build carries its own bundle id, one source can list them all, and a
tester adds it once instead of once per PR.

The entries on that release are the source of truth: a PR whose entry was
deleted drops out on the next merge, and a rebuilt PR replaces its own entry
because the workflow overwrote its file. Files that do not parse are
skipped with a warning rather than failing the whole source, so one broken
upload cannot take every other PR build offline.

Usage:
    merge_pr_sources.py --entries DIR --out pr.json --icon-url URL
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SOURCE_NAME = "Spectrum Strategy PR builds"
SOURCE_SUBTITLE = (
    "Test builds of open pull requests. Each installs as its own app; "
    "delete it when the PR merges."
)
PR_SUFFIX = re.compile(r"\.pr(\d+)$")

def parse_args(argv):
    p = argparse.ArgumentParser(description="Merge per-PR AltStore sources.")
    p.add_argument(
        "--entries",
        required=True,
        help="Directory searched recursively for source-pr<N>.json files.",
    )
    p.add_argument("--out", required=True, help="Output JSON path.")
    p.add_argument("--icon-url", required=True, help="Public icon URL.")
    return p.parse_args(argv)

def pr_number(app) -> int | None:
    """The PR number encoded in a PR build's bundle id, or None."""
    match = PR_SUFFIX.search(str(app.get("bundleIdentifier", "")))
    return int(match.group(1)) if match else None

def load_apps(entries_dir: Path):
    """Return the app entries found under entries_dir, newest PR first."""
    apps = {}
    for path in sorted(entries_dir.rglob("source-pr*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            candidates = data["apps"]
        except (OSError, ValueError, KeyError, TypeError) as exc:
            print(f"Warning: skipping {path}: {exc}", file=sys.stderr)
            continue
        for app in candidates if isinstance(candidates, list) else []:
            if not isinstance(app, dict):
                continue
            pr = pr_number(app)
            if pr is None or not app.get("versions"):
                print(
                    f"Warning: skipping {path}: not a PR build entry",
                    file=sys.stderr,
                )
                continue

            if pr in apps and _build_key(apps[pr]) >= _build_key(app):
                continue
            apps[pr] = app
    return [apps[pr] for pr in sorted(apps, reverse=True)]

def _build_key(app):
    return str(app["versions"][0].get("date", ""))

def build_source(apps, icon_url: str):
    return {
        "name": SOURCE_NAME,
        "subtitle": SOURCE_SUBTITLE,
        "iconURL": icon_url,
        "apps": apps,
        "news": [],
    }

def main(argv):
    args = parse_args(argv)
    apps = load_apps(Path(args.entries))
    source = build_source(apps, args.icon_url)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(source, fh, indent=2)
        fh.write("\n")
    print(f"Wrote {args.out} ({len(apps)} PR build(s)).")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
