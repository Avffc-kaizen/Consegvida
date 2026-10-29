#!/usr/bin/env bash
# Compiles and launches only in an Apple simulator. Never signs for a team or authenticates.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"
evidence_dir="$script_dir/build/evidence"
xtool_bin="${CONSEGVIDA_XTOOL_BIN:-xtool}"
mkdir -p "$evidence_dir"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'An Apple simulator requires a macOS runner with Xcode.' >&2
  exit 2
fi
for command_name in "$xtool_bin" xcrun python3; do
  command -v "$command_name" >/dev/null || { echo "Missing command: $command_name" >&2; exit 2; }
done
test -f Sources/ConsegVida/Resources/content.json || { echo 'Run content synchronization first.' >&2; exit 2; }
test -f Assets/AppIcon.png || { echo 'Generate the canonical app icon first.' >&2; exit 2; }

architecture="$(uname -m)"
case "$architecture" in
  arm64) triple='arm64-apple-ios-simulator' ;;
  x86_64) triple='x86_64-apple-ios-simulator' ;;
  *) echo "Unsupported simulator architecture: $architecture" >&2; exit 2 ;;
esac

"$xtool_bin" --version | tee "$evidence_dir/xtool-version.txt"
xcrun --sdk iphonesimulator --show-sdk-version | tee "$evidence_dir/apple-sdk-version.txt"
"$xtool_bin" dev build --triple "$triple" 2>&1 | tee "$evidence_dir/build.log"

app_path="$(python3 - "$script_dir/xtool" <<'PY'
import pathlib
import plistlib
import sys

root = pathlib.Path(sys.argv[1])
apps = []
for path in root.rglob('*.app'):
    info = path / 'Info.plist'
    if info.is_file():
        with info.open('rb') as stream:
            metadata = plistlib.load(stream)
        if metadata.get('CFBundleIdentifier') == 'com.consegvida.app':
            apps.append(path.resolve())
if len(apps) != 1:
    raise SystemExit(f'Expected one ConsegVida app bundle, found {len(apps)}.')
print(apps[0])
PY
)"

xcrun simctl list devices available --json > "$evidence_dir/available-simulators.json"
device_id="$(python3 - "$evidence_dir/available-simulators.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding='utf-8') as stream:
    runtimes = json.load(stream)['devices']
candidates = []
for runtime, devices in runtimes.items():
    if '.iOS-' not in runtime:
        continue
    version = tuple(int(part) for part in runtime.rsplit('.iOS-', 1)[1].split('-'))
    for device in devices:
        if device.get('isAvailable') and device.get('name', '').startswith('iPhone'):
            candidates.append((device.get('state') == 'Booted', version, device['name'], device['udid']))
if not candidates:
    raise SystemExit('No available iPhone simulator. Install a simulator runtime first.')
print(sorted(candidates, reverse=True)[0][3])
PY
)"

is_booted="$(python3 - "$evidence_dir/available-simulators.json" "$device_id" <<'PY'
import json
import sys
with open(sys.argv[1], encoding='utf-8') as stream:
    devices = json.load(stream)['devices']
print(next('yes' if d.get('state') == 'Booted' else 'no'
           for group in devices.values() for d in group if d['udid'] == sys.argv[2]))
PY
)"

if [[ "$is_booted" == 'no' ]]; then
  xcrun simctl boot "$device_id"
fi
xcrun simctl bootstatus "$device_id" -b
xcrun simctl install "$device_id" "$app_path"
xcrun simctl launch "$device_id" com.consegvida.app | tee "$evidence_dir/launch.log"
# Bounded rendering grace period; screenshot is an artifact for human review, not a UI assertion.
python3 - <<'PY'
import time
time.sleep(2)
PY
xcrun simctl io "$device_id" screenshot "$evidence_dir/consegvida-ios-launch.png"

python3 - "$app_path" "$device_id" "$evidence_dir/smoke-result.json" <<'PY'
import json
import pathlib
import plistlib
import sys
app = pathlib.Path(sys.argv[1])
with (app / 'Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
result = {
    'bundleIdentifier': info.get('CFBundleIdentifier'),
    'version': info.get('CFBundleShortVersionString'),
    'build': info.get('CFBundleVersion'),
    'simulatorUDID': sys.argv[2],
    'buildInstallLaunchCommandsSucceeded': True,
    'screenshot': 'consegvida-ios-launch.png',
    'scope': 'Simulator build, install and launch smoke only. Screenshot requires inspection.',
    'fullUserFlowTested': False,
    'physicalDeviceTested': False,
    'storeSubmitted': False
}
pathlib.Path(sys.argv[3]).write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
PY

echo 'Simulator build/install/launch smoke completed. Inspect the screenshot; this is not full E2E or a store release.'
