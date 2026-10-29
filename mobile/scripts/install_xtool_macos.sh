#!/usr/bin/env bash
# Install the reviewed upstream build into this disposable CI runner only.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo 'This installer requires macOS.' >&2; exit 2; }
: "${RUNNER_TEMP:?Run this installer in a GitHub Actions runner}"
: "${GITHUB_ENV:?GitHub Actions environment file is required}"
archive="$RUNNER_TEMP/consegvida-xtool-1.24.0.zip"
destination="$RUNNER_TEMP/consegvida-xtool"
[[ ! -e "$destination" ]] || { echo 'The xtool destination already exists.' >&2; exit 2; }
curl --fail --location --retry 2 \
  https://github.com/xtool-org/xtool/releases/download/1.24.0/xtool.app.zip \
  -o "$archive"
python3 - "$archive" <<'PY'
import hashlib
import pathlib
import sys
expected = 'a56e98d69dea02a97a17e609f0ae8771c57ffaab23f1d62513fd9ada222026b3'
actual = hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit('xtool release checksum mismatch')
PY
unzip -q "$archive" -d "$destination"
xtool_bin="$destination/xtool.app/Contents/Resources/bin/xtool"
"$xtool_bin" --version
printf '%s\n' "CONSEGVIDA_XTOOL_BIN=$xtool_bin" >> "$GITHUB_ENV"
