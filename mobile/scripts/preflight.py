#!/usr/bin/env python3
"""Read-only local build prerequisite check. Does not authenticate or publish."""
import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def inspect_tool(name, args):
    executable = shutil.which(name)
    if not executable:
        return {"available": False, "detail": "not found in PATH"}
    try:
        result = subprocess.run([executable, *args], capture_output=True, text=True, timeout=15)
        output = (result.stdout + result.stderr).strip()
        return {"available": result.returncode == 0, "detail": output[:1500]}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"available": False, "detail": str(error)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require", choices=("android", "ios", "core"))
    args = parser.parse_args()
    tools = {
        "java": inspect_tool("java", ["--version"]),
        "swift": inspect_tool("swift", ["--version"]),
        "xtool": inspect_tool("xtool", ["--version"]),
        "xcodebuild": inspect_tool("xcodebuild", ["-version"]),
    }
    sdk_path = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    sdk = Path(sdk_path) if sdk_path else None
    android_sdk = bool(sdk and (sdk / "platforms/android-36/android.jar").is_file())
    swift_sdk = inspect_tool("swift", ["sdk", "list"]) if tools["swift"]["available"] else None
    report = {
        "tools": tools,
        "android_api36": android_sdk,
        "swift_sdks": swift_sdk,
        "store_accounts": "UNVERIFIED: local tooling is not proof of developer membership",
        "signing": "UNVERIFIED: no credential access is attempted",
        "publication": "NOT_ATTEMPTED",
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    ready = {
        "android": tools["java"]["available"] and android_sdk,
        "core": tools["swift"]["available"],
        "ios": tools["swift"]["available"] and tools["xtool"]["available"] and (
            tools["xcodebuild"]["available"] or bool(swift_sdk and "darwin" in swift_sdk["detail"])
        ),
    }
    return 0 if args.require is None or ready[args.require] else 2


if __name__ == "__main__":
    sys.exit(main())
