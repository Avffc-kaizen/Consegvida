#!/usr/bin/env python3
"""Validate canonical content and sync the two SwiftPM resource copies.

Android reads the same source through its assets sourceSet. No network or
third-party Python packages are required.
"""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "mobile/shared/content.json"
TARGETS = (
    ROOT / "mobile/ios/Sources/ConsegVida/Resources/content.json",
    ROOT / "mobile/core-swift/Tests/ConsegVidaCoreTests/Fixtures/content.json",
)


def validate(content):
    philosophy = json.loads((ROOT / "src/data/philosophy.json").read_text())
    css = (ROOT / "src/styles/tokens.css").read_text()
    site = json.loads((ROOT / "src/lib/og/site.json").read_text())
    if content["schemaVersion"] != 1 or content["appName"] != site["title"]:
        raise ValueError("Unsupported content schema or inconsistent product name")
    axes = content["axes"]
    if len(axes) != 3 or {a["id"] for a in axes} != set(philosophy["axes"]):
        raise ValueError("Mobile axes differ from the committed philosophy")
    for axis in axes:
        source = philosophy["axes"][axis["id"]]
        if (axis["label"], axis["protects"]) != (source["label"], source["protects"]):
            raise ValueError("Mobile axis identity differs from canonical content")
        token = re.search(r"--cv-" + axis["id"] + r":\s*(#[0-9A-Fa-f]{6})", css)
        if token is None or token[1].lower() != axis["color"].lower():
            raise ValueError("Mobile axis color differs from canonical tokens")
    for name, color in content["colors"].items():
        css_name = "mute" if name == "muted" else name
        token = re.search(r"--cv-" + css_name + r":\s*(#[0-9A-Fa-f]{6})", css)
        if token is None or token[1].lower() != color.lower():
            raise ValueError("Mobile palette differs from canonical tokens")
    missions = content["missions"]
    if {m["id"] for m in missions} != {
        "fisico-entorno", "mental-foco", "espiritual-presenca"
    } or len(missions) != 3:
        raise ValueError("Missing or duplicate mission identifier")
    if {m["axis"] for m in missions} != set(philosophy["axes"]):
        raise ValueError("Every canonical axis must have one mission")
    for mission in missions:
        if mission["source"] != "src/data/philosophy.json#/axes/" + mission["axis"]:
            raise ValueError("Mission provenance is missing")
        if not 1 <= mission["minutes"] <= 20 or not mission["steps"]:
            raise ValueError("Mission must remain small and actionable")
        if any(not isinstance(step, str) or not step.strip() for step in mission["steps"]):
            raise ValueError("Mission steps must be meaningful strings")
    if content["manifestoURL"] != "https://www.youtube.com/watch?v=TkyLy-kIGhE":
        raise ValueError("Unexpected external link in mobile content")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify without writing")
    args = parser.parse_args()
    raw = SOURCE.read_bytes()
    validate(json.loads(raw))
    mismatches = []
    for target in TARGETS:
        if args.check:
            if not target.is_file() or target.read_bytes() != raw:
                mismatches.append(str(target.relative_to(ROOT)))
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
    if mismatches:
        print("Out-of-date mobile content: " + ", ".join(mismatches), file=sys.stderr)
        return 1
    print("Canonical content validated; sha256=" + hashlib.sha256(raw).hexdigest())
    print("SwiftPM resource copies match; Android uses mobile/shared directly.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, KeyError, ValueError, TypeError) as error:
        print("Content validation failed: " + str(error), file=sys.stderr)
        sys.exit(1)
