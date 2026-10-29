#!/usr/bin/env python3
"""Inspect the real release bundle; this never signs or uploads it."""
import hashlib
import json
from pathlib import Path
import zipfile

mobile = Path(__file__).resolve().parents[1]
bundle = mobile / "android/app/build/outputs/bundle/release/app-release.aab"
canonical = mobile / "shared/content.json"
with zipfile.ZipFile(bundle) as archive:
    names = archive.namelist()
    if archive.testzip() is not None:
        raise SystemExit("Corrupt Android App Bundle")
    for required in ("BundleConfig.pb", "base/manifest/AndroidManifest.xml", "base/dex/classes.dex"):
        if required not in names or not archive.read(required):
            raise SystemExit(f"Missing release bundle entry: {required}")
    if archive.read("base/assets/content.json") != canonical.read_bytes():
        raise SystemExit("Release bundle content differs from canonical content")
    signatures = [name for name in names if name.upper().startswith("META-INF/")
                  and name.upper().endswith((".SF", ".RSA", ".DSA", ".EC"))]
    if signatures:
        raise SystemExit("Unexpected signature: this CI must produce an unsigned release bundle")
    native_libraries = [name for name in names if name.endswith(".so")]
    if native_libraries:
        raise SystemExit("Unexpected native libraries require separate page-size compatibility review")

result = {
    "file": bundle.name,
    "sha256": hashlib.sha256(bundle.read_bytes()).hexdigest(),
    "bytes": bundle.stat().st_size,
    "unsignedReleaseBundle": True,
    "canonicalContentMatches": True,
    "nativeLibraries": [],
    "directlyInstallable": False,
    "storeSubmitted": False,
}
evidence = mobile / "android/build/evidence"
evidence.mkdir(parents=True, exist_ok=True)
(evidence / "bundle-result.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
