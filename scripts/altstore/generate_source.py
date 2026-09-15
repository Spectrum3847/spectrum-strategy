#!/usr/bin/env python3
"""Generate an AltStore source JSON for a Spectrum Strategy distribution channel.

AltStore reads a public "source" JSON and offers the newest entry in `versions[]`
for install. It decides an update exists by comparing `version`
(CFBundleShortVersionString) and `buildVersion` (CFBundleVersion) of the newest
entry against what is installed, so every build must bump one of them. The IPA we
publish is unsigned; AltStore re-signs it on device with the user's free Apple ID.

This script builds that JSON. For the stable channel it prepends the new version
to an existing source (read with --existing) so the version history is preserved;
for nightly it emits a single newest entry. The pr channel emits one entry for a
pull request's test build under a bundle id of its own
(BUNDLE_ID.pr<number>), so several PR builds install side by side in
LiveContainer and can share one source; merge_pr_sources.py combines those
per-PR files into the source testers subscribe to. Run with no network access;
the caller passes every value in.

Source schema reference: https://faq.altstore.io/developers/make-a-source
"""

import argparse
import json
import os
import sys

APP_NAME = "Spectrum Strategy"
SUBTITLE = "FRC strategy and scouting"

CHANNEL_LABELS = {
    "stable": {"suffix": "", "subtitle": SUBTITLE},
    "nightly": {
        "suffix": " Nightly",
        "subtitle": f"{SUBTITLE} - nightly builds, expect breakage",
    },

    "pr": {"suffix": " PR {pr}", "subtitle": f"{SUBTITLE} - test build of PR {{pr}}"},
}
BUNDLE_ID = "org.spectrum3847.spectrumstrategy"
DEVELOPER_NAME = "Spectrum 3847"
TINT_COLOR = "3C0060"
CATEGORY = "utilities"
APP_DESCRIPTION = "Strategy board and scouting for FRC teams."

APP_PERMISSIONS = {
    "entitlements": [],
    "privacy": {
        "NSCameraUsageDescription": "Used to scan scouting QR codes from "
        "other devices.",
    },
}

def parse_args(argv):
    p = argparse.ArgumentParser(description="Generate an AltStore source JSON.")
    p.add_argument("--channel", required=True, choices=["nightly", "stable", "pr"])
    p.add_argument(
        "--pr",
        type=int,
        default=0,
        help="Pull request number; required for --channel pr.",
    )
    p.add_argument(
        "--bundle-id",
        default="",
        help="CFBundleIdentifier read back from the built app. Defaults to the "
        "channel's expected id; pass it so a mismatch fails here, not on the "
        "phone.",
    )
    p.add_argument("--out", required=True, help="Output JSON path.")
    p.add_argument("--ipa", required=True, help="Path to the built IPA (for size).")
    p.add_argument("--version", required=True, help="CFBundleShortVersionString.")
    p.add_argument("--build-version", required=True, help="CFBundleVersion.")
    p.add_argument("--date", required=True, help="ISO 8601 timestamp.")
    p.add_argument("--download-url", required=True, help="Public IPA URL.")
    p.add_argument("--icon-url", required=True, help="Public icon URL.")
    p.add_argument("--description", default="", help="Version release notes.")
    p.add_argument("--min-os", default="13.0", help="Minimum iOS version.")
    p.add_argument(
        "--existing",
        default="",
        help="Path to the current source JSON to merge into (stable history). "
        "Missing or unreadable is treated as no history.",
    )
    args = p.parse_args(argv)
    if args.channel == "pr" and args.pr <= 0:
        p.error("--channel pr requires --pr <number>")
    return args

def pr_bundle_id(pr: int) -> str:
    """The bundle id a PR test build is built with (see pr-build.yml)."""
    return f"{BUNDLE_ID}.pr{pr}"

def expected_bundle_id(args) -> str:
    return pr_bundle_id(args.pr) if args.channel == "pr" else BUNDLE_ID

def _warn_suspicious_version(version: str) -> None:
    """Heuristic guard for a version string that looks requested rather than built.

    A real CFBundleShortVersionString read from a built Info.plist is numeric
    (dots only). A hyphen typically means the caller passed the *requested*
    build-name (e.g. "0.0.0-nightly" or "1.0.0-rc.13") instead of the value
    Xcode actually baked in, which mismatches the IPA and breaks plain AltStore
    installs. Warn only -- the caller knows whether a hyphen is legitimate.
    """
    if "-" in version:
        print(
            f"Warning: --version '{version}' contains a '-' which usually means "
            "it was not read back from the built Info.plist.",
            file=sys.stderr,
        )

RETIRED_RELEASE_HOST = "Spectrum3847/spectrum-strategy-releases"
CURRENT_RELEASE_HOST = "Spectrum3847/spectrum-strategy"

def load_existing_versions(path):
    """Return the existing versions[] list, or [] if there is none."""
    if not path or not os.path.exists(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        versions = data["apps"][0].get("versions", [])
        for version in versions:
            url = version.get("downloadURL")
            if isinstance(url, str) and RETIRED_RELEASE_HOST in url:
                version["downloadURL"] = url.replace(
                    RETIRED_RELEASE_HOST, CURRENT_RELEASE_HOST
                )
        return versions
    except (
        ValueError,
        KeyError,
        IndexError,
        OSError,
        AttributeError,
        TypeError,
    ) as exc:

        print(
            f"Warning: could not load existing source JSON from '{path}': {exc}. "
            "Version history will not be preserved.",
            file=sys.stderr,
        )
        return []

def build_source(args):
    label = CHANNEL_LABELS[args.channel]
    pr = getattr(args, "pr", 0)
    channel_name = f"{APP_NAME}{label['suffix']}".format(pr=pr)
    subtitle = label["subtitle"].format(pr=pr)
    bundle_id = getattr(args, "bundle_id", "") or expected_bundle_id(args)
    if bundle_id != expected_bundle_id(args):
        raise ValueError(
            f"built bundle id {bundle_id!r} does not match the {args.channel} "
            f"channel's {expected_bundle_id(args)!r}; the source would "
            "advertise an app the IPA is not"
        )

    size = os.path.getsize(args.ipa)
    new_version = {
        "version": args.version,
        "buildVersion": args.build_version,
        "date": args.date,
        "localizedDescription": args.description
        or f"{channel_name} {args.version}.",
        "downloadURL": args.download_url,
        "size": size,
        "minOSVersion": args.min_os,
    }

    if args.channel == "stable":
        history = load_existing_versions(args.existing)

        history = [
            v
            for v in history
            if not (
                v.get("version") == args.version
                and v.get("buildVersion") == args.build_version
            )
        ]

        versions = [new_version] + history
    else:

        versions = [new_version]

    return {
        "name": channel_name,
        "subtitle": subtitle,
        "iconURL": args.icon_url,
        "apps": [
            {
                "name": channel_name,
                "bundleIdentifier": bundle_id,
                "developerName": DEVELOPER_NAME,
                "localizedDescription": APP_DESCRIPTION,
                "iconURL": args.icon_url,
                "tintColor": TINT_COLOR,
                "category": CATEGORY,

                "appPermissions": APP_PERMISSIONS,
                "versions": versions,
            }
        ],
        "news": [],
    }

def main(argv):
    args = parse_args(argv)
    _warn_suspicious_version(args.version)
    source = build_source(args)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(source, fh, indent=2)
        fh.write("\n")
    print(f"Wrote {args.out} ({len(source['apps'][0]['versions'])} version(s)).")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
