#!/usr/bin/env bash
# Manual Apple distribution only. No credentials are accepted as command-line arguments.
set -euo pipefail
umask 077
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
python3 - "$repo_root" <<'PY'
import base64
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import plistlib
import re
import secrets
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile


class DistributionError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise DistributionError(message)


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=')


def jose_signature(der):
    # OpenSSL returns an ASN.1 DER ECDSA signature; JWT ES256 uses fixed-width R || S.
    def item(offset, tag):
        require(offset + 2 <= len(der) and der[offset] == tag, 'Invalid signing-tool response.')
        length = der[offset + 1]
        start = offset + 2
        if length & 128:
            count = length & 127
            require(0 < count <= 2 and start + count <= len(der), 'Invalid signing-tool response.')
            length = int.from_bytes(der[start:start + count], 'big')
            start += count
        require(start + length <= len(der), 'Invalid signing-tool response.')
        return start, start + length
    start, end = item(0, 0x30)
    r_start, r_end = item(start, 0x02)
    s_start, s_end = item(r_end, 0x02)
    require(end == len(der) and s_end == end, 'Invalid signing-tool response.')
    numbers = [int.from_bytes(der[a:b], 'big') for a, b in ((r_start, r_end), (s_start, s_end))]
    require(all(0 < n < 2**256 for n in numbers), 'Invalid signing-tool response.')
    return b''.join(n.to_bytes(32, 'big') for n in numbers)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        return None  # Never forward an Authorization header to a redirected host.


class Distribution:
    def __init__(self, root):
        self.root = root.resolve()
        self.private = None
        self.keychain = None
        self.previous_search = None
        self.previous_default = None
        self.log_count = 0
        self.stage = 'configuration'
        self.config = {name: os.environ.pop(name, '') for name in (
            'APPLE_TEAM_ID', 'ASC_APP_ID', 'ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_PRIVATE_KEY_P8')}

    def summary(self, message):
        print(message, flush=True)
        destination = os.environ.get('GITHUB_STEP_SUMMARY')
        if destination:
            with open(destination, 'a', encoding='utf-8') as stream:
                stream.write(message + '\n\n')

    def tool(self, args, label, input_data=None, timeout=900):
        self.log_count += 1
        path = self.private / f'tool-{self.log_count}.log'
        try:
            with path.open('wb') as log:
                process = subprocess.run(args, cwd=self.root, input=input_data,
                                         stdout=log, stderr=subprocess.STDOUT,
                                         timeout=timeout, env={**os.environ, 'TMPDIR': str(self.private) + '/'})
        except (OSError, subprocess.TimeoutExpired):
            raise DistributionError(f'{label}: tool unavailable or timed out; no automatic upload retry.') from None
        output = path.read_bytes()
        if process.returncode:
            # Full Apple logs may contain credential/account information. Keep them private
            # until cleanup and emit only fixed diagnostic categories, never their contents.
            lower = output.lower()
            category = 'Check the Apple account configuration and permissions.'
            if b'no team found in archive' in lower:
                category = 'The archive has no valid Apple team.'
            elif b'user interaction is not allowed' in lower:
                category = 'The temporary signing keychain requires unattended signing access.'
            elif b'no devices' in lower or b'no registered devices' in lower:
                category = 'The development profile needs an existing registered iOS device. This workflow does not register devices.'
            elif b'certificate' in lower or b'provisioning profile' in lower:
                category = 'Check certificate/profile permissions, existing identities and certificate quotas.'
            elif b'401' in lower or b'403' in lower or b'authentication' in lower:
                category = 'Check the team API key, role and cloud-signing access.'
            raise DistributionError(f'{label} failed (exit {process.returncode}). {category}')
        return output

    def configure(self):
        require(platform.system() == 'Darwin' and os.environ.get('RUNNER_OS') == 'macOS',
                'This workflow requires an ephemeral macOS GitHub runner with Xcode.')
        require(os.environ.get('GITHUB_ACTIONS') == 'true'
                and os.environ.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
                and os.environ.get('GITHUB_REPOSITORY') == 'Avffc-kaizen/Consegvida'
                and os.environ.get('GITHUB_REF') == 'refs/heads/main',
                'Only a manual workflow on main in the Consegvida repository may distribute.')
        formats = {'APPLE_TEAM_ID': r'[A-Z0-9]{10}', 'ASC_APP_ID': r'[1-9][0-9]{5,19}',
                   'ASC_KEY_ID': r'[A-Z0-9]{10}',
                   'ASC_ISSUER_ID': r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'}
        for name, pattern in formats.items():
            require(re.fullmatch(pattern, self.config[name]) is not None, f'Missing or invalid {name}.')
        key_text = self.config.pop('ASC_PRIVATE_KEY_P8').strip().replace('\r\n', '\n')
        require(100 <= len(key_text) <= 16384 and key_text.startswith('-----BEGIN PRIVATE KEY-----\n')
                and key_text.endswith('\n-----END PRIVATE KEY-----'),
                'ASC_PRIVATE_KEY_P8 must contain an unencrypted Apple team API private key in PEM format.')
        self.private = Path(tempfile.mkdtemp(prefix='consegvida-testflight-', dir=os.environ.get('RUNNER_TEMP')))
        self.private.chmod(0o700)
        self.key = self.private / 'AuthKey.p8'
        with self.key.open('x', encoding='utf-8') as stream:
            stream.write(key_text + '\n')
        self.key.chmod(0o600)
        key_text = ''
        public = self.tool(['/usr/bin/openssl', 'pkey', '-in', str(self.key), '-pubout', '-outform', 'DER'],
                           'Validate API key', input_data=b'', timeout=15)
        require(len(public) == 91 and public.startswith(bytes.fromhex(
            '3059301306072a8648ce3d020106082a8648ce3d03010703420004')),
            'The API key must be an EC P-256 key suitable for ES256.')
        revision = self.tool(['git', 'rev-parse', 'HEAD'], 'Read checkout revision').decode().strip()
        require(re.fullmatch(r'[0-9a-f]{40}', revision) and revision == os.environ.get('GITHUB_SHA'),
                'The checkout does not match the manually selected commit.')
        self.revision = revision
        xcode = self.tool(['xcrun', 'xcodebuild', '-version'], 'Read Xcode version').decode()
        require(re.search(r'^Xcode 26\.6\s*$', xcode, re.MULTILINE), 'Use the reviewed Xcode 26.6 toolchain.')
        help_text = self.tool(['xcrun', 'xcodebuild', '-help'], 'Read Xcode distribution options').decode()
        for value in ('app-store-connect', 'destination', 'signingStyle', 'teamID',
                      'manageAppVersionAndBuildNumber', '-authenticationKeyPath'):
            require(value in help_text, 'The selected Xcode does not expose the reviewed distribution options.')
        manifest = (self.root / 'mobile/ios/xtool.yml').read_text(encoding='utf-8')
        identifiers = re.findall(r'^bundleID:\s*([A-Za-z0-9.-]+)\s*$', manifest, re.MULTILINE)
        require(len(identifiers) == 1, 'Could not read the existing bundle identifier.')
        self.bundle_id = identifiers[0]
        info = plistlib.loads((self.root / 'mobile/ios/Info.plist').read_bytes())
        self.version, self.build = info['CFBundleShortVersionString'], info['CFBundleVersion']
        require(all(isinstance(value, str) and re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', value)
                    for value in (self.version, self.build)), 'Invalid source version/build metadata.')

    def token(self):
        header = b64url(json.dumps({'alg': 'ES256', 'kid': self.config['ASC_KEY_ID'], 'typ': 'JWT'},
                                  separators=(',', ':')).encode())
        now = int(time.time())
        claims = b64url(json.dumps({'iss': self.config['ASC_ISSUER_ID'], 'iat': now - 30,
                                   'exp': now + 300, 'aud': 'appstoreconnect-v1'},
                                  separators=(',', ':')).encode())
        unsigned = header + b'.' + claims
        signature = self.tool(['/usr/bin/openssl', 'dgst', '-sha256', '-sign', str(self.key)],
                              'Authenticate Apple API request', input_data=unsigned, timeout=15)
        return (unsigned + b'.' + b64url(jose_signature(signature))).decode('ascii')

    def get(self, path, query=None):
        url = 'https://api.appstoreconnect.apple.com/v1/' + path
        if query:
            url += '?' + urllib.parse.urlencode(query)
        request = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + self.token(),
                                                      'Accept': 'application/json'})
        try:
            with urllib.request.build_opener(NoRedirect()).open(request, timeout=30) as response:
                raw = response.read(2 * 1024 * 1024 + 1)
        except urllib.error.HTTPError as error:
            raise DistributionError(f'Apple metadata precondition failed (HTTP {error.code}); check account access.') from None
        except (OSError, urllib.error.URLError):
            raise DistributionError('Apple metadata request failed; no upload was retried.') from None
        require(len(raw) <= 2 * 1024 * 1024, 'Apple metadata response exceeded its limit.')
        try:
            result = json.loads(raw)
        except ValueError:
            raise DistributionError('Invalid Apple metadata response.') from None
        require(not result.get('links', {}).get('next'), 'Unexpected paginated response; refusing an incomplete check.')
        return result

    def builds(self):
        result = self.get('builds', {'filter[app]': self.config['ASC_APP_ID'], 'filter[version]': self.build,
                                   'filter[preReleaseVersion.version]': self.version,
                                   'filter[preReleaseVersion.platform]': 'IOS', 'include': 'preReleaseVersion',
                                   'limit': '2'})
        records = result.get('data')
        require(isinstance(records, list) and len(records) <= 1, 'Unexpected build-query result.')
        included = {entry['id']: entry for entry in result.get('included', [])
                    if entry.get('type') == 'preReleaseVersions'}
        for record in records:
            related = record.get('relationships', {}).get('preReleaseVersion', {}).get('data', {})
            prerelease = included.get(related.get('id'), {}).get('attributes', {})
            require(record.get('attributes', {}).get('version') == self.build
                    and prerelease.get('version') == self.version and prerelease.get('platform') == 'IOS',
                    'Apple build metadata does not match the requested version/platform.')
        return records

    def preflight(self):
        self.stage = 'Apple preconditions'
        app = self.get('apps/' + self.config['ASC_APP_ID'], {'fields[apps]': 'bundleId'}).get('data', {})
        require(app.get('id') == self.config['ASC_APP_ID']
                and app.get('attributes', {}).get('bundleId') == self.bundle_id,
                'The existing App Store Connect app does not match the source bundle identifier.')
        bundles = self.get('bundleIds', {'filter[identifier]': self.bundle_id, 'limit': '2'}).get('data')
        require(isinstance(bundles, list) and len(bundles) == 1
                and bundles[0].get('attributes', {}).get('identifier') == self.bundle_id,
                'An accessible explicit App ID must already exist for the source bundle identifier.')
        require(not self.builds(), 'This version/build already exists in App Store Connect. No upload or version change was performed.')
        self.summary('Apple app record and explicit bundle ID verified; the source version/build is unused.')

    def prepare_project(self):
        self.stage = 'unsigned project preparation'
        self.summary('Preparing the validated xtool project and device assets; no Apple credentials are passed to this build.')
        self.tool(['python3', 'mobile/scripts/sync_content.py', '--check'], 'Validate canonical content')
        self.tool(['bash', 'mobile/ios/ci-archive-unsigned.sh'], 'Prepare xtool project and unsigned archive', timeout=1200)
        artifacts = self.root / 'mobile/ios/build/artifacts/unsigned-ios'
        report = json.loads((artifacts / 'archive-validation.json').read_text())
        require(all(report.get(key) is True for key in ('deviceArchiveValidated', 'processedAppIconValidated',
                                                       'privacyManifestValidated', 'canonicalContentValidated'))
                and report.get('sourceRevision') == self.revision and report.get('bundleIdentifier') == self.bundle_id
                and report.get('version') == self.version and report.get('build') == self.build,
                'The unsigned preparation report does not match this checkout.')
        digests = {}
        for line in (artifacts / 'SHA256SUMS.txt').read_text().splitlines():
            digest, name = line.split('  ', 1)
            require(Path(name).name == name and re.fullmatch(r'[a-f0-9]{64}', digest), 'Invalid artifact checksum manifest.')
            digests[name] = digest
        project_zip = artifacts / 'ConsegVida-Xcode-project.zip'
        require(hashlib.sha256(project_zip.read_bytes()).hexdigest() == digests.get(project_zip.name),
                'The generated Xcode project checksum does not match.')
        destination = self.private / 'project'
        destination.mkdir()
        with zipfile.ZipFile(project_zip) as zipped:
            entries = zipped.infolist()
            require(len(entries) <= 2000 and sum(entry.file_size for entry in entries) <= 100 * 1024 * 1024,
                    'The generated project archive exceeds its limits.')
            seen = set()
            for entry in entries:
                relative = PurePosixPath(entry.filename.replace(chr(92), '/'))
                target = (destination / relative).resolve()
                require(not relative.is_absolute() and '..' not in relative.parts
                        and target.is_relative_to(destination) and target not in seen
                        and not stat.S_ISLNK(entry.external_attr >> 16), 'Unsafe generated project archive entry.')
                seen.add(target)
                if entry.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with zipped.open(entry) as source, target.open('wb') as output:
                        shutil.copyfileobj(source, output)
        self.project_ios = destination / 'ConsegVida-Xcode/mobile/ios'
        self.workspace = self.project_ios / 'xtool/ConsegVida.xcworkspace'
        require(self.workspace.is_dir(), 'The portable Xcode workspace is missing.')
        self.scheme = report['scheme']

    def setup_keychain(self):
        self.previous_search = shlex.split(self.tool(['security', 'list-keychains', '-d', 'user'],
                                                     'Read keychain search configuration').decode())
        default = shlex.split(self.tool(['security', 'default-keychain', '-d', 'user'],
                                        'Read default keychain configuration').decode())
        require(len(default) == 1 and self.previous_search, 'Could not preserve the runner keychain configuration.')
        self.previous_default = default[0]
        password = secrets.token_urlsafe(32)
        keychain = self.private / 'ci-signing.keychain-db'
        self.tool(['security', 'create-keychain', '-p', password, str(keychain)], 'Create temporary signing keychain')
        self.keychain = keychain
        self.tool(['security', 'set-keychain-settings', '-lut', '21600', str(keychain)], 'Configure temporary keychain')
        self.tool(['security', 'unlock-keychain', '-p', password, str(keychain)], 'Unlock temporary keychain')
        self.tool(['security', 'list-keychains', '-d', 'user', '-s', str(keychain)], 'Select temporary keychain')
        self.tool(['security', 'default-keychain', '-d', 'user', '-s', str(keychain)], 'Select default temporary keychain')
        password = ''

    def auth_args(self):
        return ['-allowProvisioningUpdates', '-authenticationKeyPath', str(self.key),
                '-authenticationKeyID', self.config['ASC_KEY_ID'],
                '-authenticationKeyIssuerID', self.config['ASC_ISSUER_ID']]

    def sign_archive(self):
        self.stage = 'development signing'
        self.summary('Automatic signing may create/update an Apple Development certificate and provisioning profiles. '
                     'Local cleanup does not revoke Apple account resources; no automatic revocation is performed.')
        self.setup_keychain()
        self.archive = self.private / 'ConsegVida-signed.xcarchive'
        self.tool(['xcrun', 'xcodebuild', '-workspace', str(self.workspace), '-scheme', self.scheme,
                   '-configuration', 'Release', '-destination', 'generic/platform=iOS',
                   '-derivedDataPath', str(self.private / 'DerivedData'), '-archivePath', str(self.archive),
                   'DEVELOPMENT_TEAM=' + self.config['APPLE_TEAM_ID'], 'CODE_SIGN_STYLE=Automatic',
                   'CODE_SIGNING_ALLOWED=YES', *self.auth_args(), 'archive'],
                  'Create developer-signed archive', timeout=1200)
        archive_info = plistlib.loads((self.archive / 'Info.plist').read_bytes())
        properties = archive_info.get('ApplicationProperties', {})
        app = (self.archive / 'Products' / properties.get('ApplicationPath', '')).resolve()
        require(app.is_relative_to(self.archive) and app.suffix == '.app' and app.is_dir(), 'Invalid signed archive application path.')
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        require(info.get('CFBundleIdentifier') == self.bundle_id
                and info.get('CFBundleShortVersionString') == self.version and info.get('CFBundleVersion') == self.build
                and info.get('CFBundleSupportedPlatforms') == ['iPhoneOS'], 'Signed archive identity/version/platform mismatch.')
        self.tool(['codesign', '--verify', '--deep', '--strict', str(app)], 'Verify development signature')
        signing = self.tool(['codesign', '--display', '--verbose=4', str(app)], 'Inspect development signature').decode()
        require('TeamIdentifier=' + self.config['APPLE_TEAM_ID'] in signing and 'Authority=Apple Development:' in signing,
                'The archive must be signed by an Apple Development identity for the configured team.')
        profile_data = self.tool(['security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')],
                                 'Inspect development provisioning profile')
        profile = plistlib.loads(profile_data)
        entitlements = profile.get('Entitlements', {})
        require(profile.get('TeamIdentifier') == [self.config['APPLE_TEAM_ID']]
                and entitlements.get('com.apple.developer.team-identifier') == self.config['APPLE_TEAM_ID']
                and entitlements.get('application-identifier', '').endswith('.' + self.bundle_id)
                and entitlements.get('get-task-allow') is True, 'Unexpected development provisioning profile.')
        require(plistlib.loads((app / 'PrivacyInfo.xcprivacy').read_bytes()) ==
                plistlib.loads((self.root / 'mobile/ios/PrivacyInfo.xcprivacy').read_bytes()), 'Signed archive privacy manifest mismatch.')
        content = list(app.rglob('content.json'))
        require(len(content) == 1 and content[0].read_bytes() == (self.root / 'mobile/shared/content.json').read_bytes(),
                'Signed archive canonical content mismatch.')
        compiled = self.project_ios / 'DistributionAssets/Compiled'
        require(all((app / item.name).is_file() and (app / item.name).read_bytes() == item.read_bytes()
                    for item in compiled.iterdir() if item.is_file()), 'Signed archive processed icon resources mismatch.')
        self.summary('Developer-signed iOS archive verified for the configured team; source version/build preserved.')

    def upload(self):
        self.stage = 'App Store Connect upload'
        require(not self.builds(), 'The version/build appeared in App Store Connect during preparation; upload cancelled.')
        options = {'method': 'app-store-connect', 'destination': 'upload', 'signingStyle': 'automatic',
                   'teamID': self.config['APPLE_TEAM_ID'], 'manageAppVersionAndBuildNumber': False,
                   'uploadSymbols': True}
        options_path = self.private / 'ExportOptions.plist'
        with options_path.open('wb') as stream:
            plistlib.dump(options, stream)
        self.tool(['xcrun', 'xcodebuild', '-exportArchive', '-archivePath', str(self.archive),
                   '-exportPath', str(self.private / 'export'), '-exportOptionsPlist', str(options_path),
                   *self.auth_args()], 'Cloud-sign and upload to App Store Connect', timeout=900)
        self.summary('Xcode completed the App Store Connect upload. This is not App Store approval or public TestFlight availability.')
        self.stage = 'Apple processing'
        # Only GET requests are repeated. Never retry export/upload automatically.
        for attempt in range(6):
            records = self.builds()
            if records:
                state = records[0].get('attributes', {}).get('processingState')
                require(state in ('PROCESSING', 'VALID', 'FAILED', 'INVALID'), 'Unexpected Apple processing state.')
                require(state not in ('FAILED', 'INVALID'), 'Apple rejected build processing. Review App Store Connect; do not blindly re-upload.')
                if state == 'VALID':
                    self.summary('Apple processing status: VALID. Configure TestFlight groups/review in App Store Connect.')
                    return
            if attempt < 5:
                time.sleep(30)
        self.summary('Upload completed; Apple processing is still pending. Check App Store Connect before any new run.')

    def cleanup(self):
        errors = []
        if self.keychain:
            for args in (['security', 'default-keychain', '-d', 'user', '-s', self.previous_default],
                         ['security', 'list-keychains', '-d', 'user', '-s', *self.previous_search],
                         ['security', 'delete-keychain', str(self.keychain)]):
                try:
                    self.tool(args, 'Restore runner keychain configuration', timeout=20)
                except DistributionError:
                    errors.append('keychain cleanup')
        if self.private:
            try:
                shutil.rmtree(self.private)
            except OSError:
                errors.append('temporary file cleanup')
        return errors


def main(root):
    distribution = Distribution(root)
    status = 1
    def interrupted(signum, frame):
        raise DistributionError('Workflow interrupted; upload will not be retried automatically.')
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, interrupted)
    try:
        distribution.configure()
        distribution.preflight()
        distribution.prepare_project()
        distribution.sign_archive()
        distribution.upload()
        status = 0
    except DistributionError as error:
        distribution.summary('Stopped at ' + distribution.stage + ': ' + str(error))
    except Exception:
        # Do not expose subprocess arguments, API responses, private paths or secrets in tracebacks.
        distribution.summary('Stopped at ' + distribution.stage + ': unexpected local/tool response; no automatic retry.')
    finally:
        if distribution.cleanup():
            distribution.summary('Temporary credential/keychain cleanup did not finish; this ephemeral runner must be discarded.')
            status = 1
    return status


if __name__ == '__main__':
    sys.exit(main(Path(sys.argv[1])))
PY
