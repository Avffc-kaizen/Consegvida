#!/usr/bin/env bash
# Device archive for inspection and later authorised distribution signing.
# Uses xtool's public Xcode generator; never authenticates, signs, exports or uploads.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
xtool_bin="${CONSEGVIDA_XTOOL_BIN:-xtool}"
if [[ "$(uname -s)" != 'Darwin' ]]; then
  echo 'An iOS device archive requires a macOS runner with full Xcode.' >&2
  exit 2
fi
for command_name in "$xtool_bin" xcrun python3 plutil ditto codesign; do
  command -v "$command_name" >/dev/null || { echo "Missing command: $command_name" >&2; exit 2; }
done

python3 - "$script_dir" "$xtool_bin" <<'PY'
import atexit
import hashlib
import json
import os
import pathlib
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

ios = pathlib.Path(sys.argv[1]).resolve()
mobile = ios.parent
xtool = str(pathlib.Path(shutil.which(sys.argv[2])).resolve())
artifacts = ios / 'build/artifacts/unsigned-ios'
if artifacts.exists():
    raise SystemExit(f'Previous generated output exists: {artifacts}. Move it before another run.')
evidence = ios / 'build/evidence/archive-unsigned'
evidence.mkdir(parents=True, exist_ok=True)
atexit.register(lambda: print(f'Archive diagnostics: {evidence}'))
work = pathlib.Path(tempfile.mkdtemp(prefix='archive-work.', dir=ios / 'build'))
source = work / 'ConsegVida-Xcode'
staged_ios = source / 'mobile/ios'
output = work / 'artifacts'
output.mkdir()
bundle_id = 'com.consegvida.app'


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def run(arguments, log_name, cwd=None, quiet=False):
    # Argument arrays keep paths and empty signing settings literal; no shell expansion.
    with (evidence / log_name).open('w', encoding='utf-8') as log:
        log.write(json.dumps(arguments) + '\n')
        log.flush()
        process = subprocess.Popen(arguments, cwd=cwd, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, bufsize=1)
        lines = []
        for line in process.stdout:
            lines.append(line)
            log.write(line)
            if not quiet:
                print(line, end='', flush=True)
        result = process.wait()
    require(result == 0, f'Command failed ({result}); see {evidence / log_name}')
    return ''.join(lines)


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def read_plist(path):
    with path.open('rb') as stream:
        return plistlib.load(stream)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


version = run([xtool, '--version'], 'xtool-version.txt').strip()
require(re.findall(r'(?<![\d.])\d+\.\d+\.\d+(?![\d.])', version) == ['1.24.0'],
        'This script is reviewed for xtool 1.24.0. Review newer generator versions first.')
xcode_version = run(['xcrun', 'xcodebuild', '-version'], 'xcode-version.txt').strip()
sdk_version = run(['xcrun', '--sdk', 'iphoneos', '--show-sdk-version'], 'iphoneos-sdk-version.txt').strip()

# Fail on configuration drift instead of silently discarding future entitlements/extensions.
expected_manifest = '''version: 1
bundleID: com.consegvida.app
product: ConsegVida
infoPath: Info.plist
iconPath: Assets/AppIcon.png
resources:
  - PrivacyInfo.xcprivacy'''
require((ios / 'xtool.yml').read_text(encoding='utf-8').strip() == expected_manifest,
        'xtool.yml changed. Review the distribution resource configuration in this script.')
canonical_content = (mobile / 'shared/content.json').read_bytes()
require((ios / 'Sources/ConsegVida/Resources/content.json').read_bytes() == canonical_content,
        'Run canonical content synchronization before archiving.')
png = (ios / 'Assets/AppIcon.png').read_bytes()
require(png[:8] == b'\x89PNG\r\n\x1a\n' and len(png) > 29
        and struct.unpack('>II', png[16:24]) == (1024, 1024) and png[25] == 2,
        'The canonical app icon must be a 1024×1024 RGB PNG without an alpha channel.')

# The local Swift package dependency remains ../core-swift in the portable project.
source_entries = [
    'ios/Package.swift', 'ios/Info.plist', 'ios/PrivacyInfo.xcprivacy',
    'ios/Sources', 'ios/Assets', 'core-swift/Package.swift',
    'core-swift/Sources', 'core-swift/Tests', 'shared/content.json',
]
source_hashes = {}
for relative in source_entries:
    original = mobile / relative
    destination = source / 'mobile' / relative
    members = list(original.rglob('*')) if original.is_dir() else [original]
    require(not original.is_symlink() and all(not p.is_symlink() for p in members),
            f'Source inputs must be ordinary files/directories: {original}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    if original.is_dir():
        shutil.copytree(original, destination)
    else:
        shutil.copy2(original, destination)
    for path in members:
        if path.is_file():
            source_hashes[str(path.relative_to(mobile))] = digest(path)
write_json(evidence / 'source-sha256.json', {
    'scope': 'Repository inputs before the staged Info.plist receives generated icon metadata.',
    'pathsRelativeTo': 'mobile', 'files': source_hashes,
})

# Apple's Single Size iOS icon catalog. actool creates all required variations;
# its partial plist and compiled resources enter xtool via supported public fields.
# Sources: xtool 1.24.0 Sources/PackLib/{Planner,XcodePacker}.swift;
# swiftlang/swift-build Sources/SWBApplePlatform/Specs/AssetCatalogCompiler.xcspec.
distribution = staged_ios / 'DistributionAssets'
catalog = distribution / 'Assets.xcassets'
icon_set = catalog / 'AppIcon.appiconset'
compiled = distribution / 'Compiled'
icon_set.mkdir(parents=True)
compiled.mkdir()
write_json(catalog / 'Contents.json', {'info': {'author': 'xcode', 'version': 1}})
write_json(icon_set / 'Contents.json', {
    'images': [{'filename': 'AppIcon.png', 'idiom': 'universal',
                'platform': 'ios', 'size': '1024x1024'}],
    'info': {'author': 'xcode', 'version': 1},
})
shutil.copy2(staged_ios / 'Assets/AppIcon.png', icon_set / 'AppIcon.png')
partial_info = distribution / 'assetcatalog-info.plist'
run(['xcrun', '--sdk', 'iphoneos', 'actool', str(catalog),
     '--compile', str(compiled), '--output-format', 'human-readable-text',
     '--notices', '--warnings', '--app-icon', 'AppIcon', '--compress-pngs',
     '--enable-on-demand-resources', 'NO', '--development-region', 'pt_BR',
     '--target-device', 'iphone', '--target-device', 'ipad',
     '--minimum-deployment-target', '17.0', '--platform', 'iphoneos',
     '--output-partial-info-plist', str(partial_info)], 'actool.log')
require((compiled / 'Assets.car').is_file(), 'actool did not produce Assets.car.')
icons_info = read_plist(partial_info)
for key in ('CFBundleIcons', 'CFBundleIcons~ipad'):
    require(icons_info.get(key, {}).get('CFBundlePrimaryIcon', {}).get('CFBundleIconName') == 'AppIcon',
            f'actool did not produce the expected {key} metadata.')
info = read_plist(staged_ios / 'Info.plist')
info.update(icons_info)
with (staged_ios / 'Info.plist').open('wb') as stream:
    plistlib.dump(info, stream)
compiled_files = sorted(p for p in compiled.iterdir() if p.is_file())
require(len(compiled_files) == len(list(compiled.iterdir())), 'Unexpected nested actool output.')
write_json(staged_ios / 'xtool.yml', {
    'version': 1, 'bundleID': bundle_id, 'product': 'ConsegVida', 'infoPath': 'Info.plist',
    'resources': ['PrivacyInfo.xcprivacy'] + [str(p.relative_to(staged_ios)) for p in compiled_files],
})  # JSON is valid YAML; xtool uses Yams. No edits to the generated pbxproj.
run([xtool, 'dev', 'generate-xcode-project'], 'generate-xcode-project.log', cwd=staged_ios)

# These locations are defined by XcodePacker in the pinned upstream tag.
workspace = staged_ios / 'xtool/ConsegVida.xcworkspace'
project = staged_ios / 'xtool/.xtool-tmp/ConsegVida.xcodeproj'
require(workspace.is_dir() and project.is_dir(), 'The official generator output layout changed.')
project_json = json.loads(run(['plutil', '-convert', 'json', '-o', '-',
                              str(project / 'project.pbxproj')], 'project.json.log', quiet=True))
targets = [obj for obj in project_json['objects'].values()
           if obj.get('isa') == 'PBXNativeTarget'
           and obj.get('productType') == 'com.apple.product-type.application']
require(len(targets) == 1, 'Expected one generated iOS application target.')
scheme = targets[0]['name']
listing = run(['xcrun', 'xcodebuild', '-list', '-json', '-workspace', str(workspace)],
              'xcode-project-list.log', quiet=True)
try:
    listed, _ = json.JSONDecoder().raw_decode(listing[listing.index('{'):])
except (ValueError, json.JSONDecodeError) as error:
    raise SystemExit(f'Could not read Xcode scheme discovery: {error}')
require(scheme in listed.get('workspace', {}).get('schemes', []),
        f'The generated application scheme {scheme!r} is unavailable; inspect the generator output.')

archive = work / 'ConsegVida-unsigned.xcarchive'
archive_command = [
    'xcrun', 'xcodebuild', '-workspace', str(workspace), '-scheme', scheme,
    '-configuration', 'Release', '-destination', 'generic/platform=iOS',
    '-derivedDataPath', str(work / 'DerivedData'), '-archivePath', str(archive),
    'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY=',
    'DEVELOPMENT_TEAM=', 'PROVISIONING_PROFILE_SPECIFIER=', 'PROVISIONING_PROFILE=',
    'archive',
]
# Do not set SKIP_INSTALL globally: dependencies must remain excluded from Products.
# No -allowProvisioningUpdates, authentication options, codesign operation or exportArchive.
run(archive_command, 'xcodebuild-archive.log')
archive_info = read_plist(archive / 'Info.plist')
application_properties = archive_info.get('ApplicationProperties', {})
application_path = application_properties.get('ApplicationPath')
require(isinstance(application_path, str), 'Generic archive: missing ApplicationProperties/ApplicationPath.')
app = (archive / 'Products' / application_path).resolve()
apps = list((archive / 'Products/Applications').glob('*.app'))
require(app.is_relative_to(archive) and len(apps) == 1 and app == apps[0].resolve(),
        'Archive must contain exactly one top-level application.')
require({p.name for p in (archive / 'Products').iterdir()} == {'Applications'},
        'Generic archive: unexpected dependency products outside the application.')
app_info = read_plist(app / 'Info.plist')
require(app_info.get('CFBundleIdentifier') == bundle_id, 'Archived bundle identifier differs from the app.')
for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
    require(app_info.get(key) == info[key], f'Archived {key} differs from the source.')
require(app_info.get('CFBundleSupportedPlatforms') == ['iPhoneOS']
        and app_info.get('DTPlatformName') == 'iphoneos', 'Archive is not built for an iOS device.')
executable = app / app_info['CFBundleExecutable']
build_version = run(['xcrun', 'vtool', '-show-build', str(executable)], 'macho-build-version.txt')
platforms = re.findall(r'^\s*platform\s+(\S+)\s*$', build_version, re.MULTILINE)
require(platforms and set(platforms) == {'IOS'}, 'Mach-O does not exclusively target the iOS device platform.')
require(not list(app.rglob('embedded.mobileprovision')), 'An unsigned archive must not contain provisioning profiles.')
inspection = subprocess.run(['codesign', '--display', '--verbose=4', str(app)],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                            env={**os.environ, 'LC_ALL': 'C'})
(evidence / 'signature-inspection.txt').write_text(inspection.stdout, encoding='utf-8')
if inspection.returncode == 0:
    require('Signature=adhoc' in inspection.stdout and 'Authority=' not in inspection.stdout
            and not re.search(r'^TeamIdentifier=(?!not set$).+', inspection.stdout, re.MULTILINE),
            'Unexpected identity signature on the archive.')
    signature = 'linker ad hoc only; no developer identity'
else:
    require('code object is not signed' in inspection.stdout, 'Could not verify that the app is unsigned.')
    signature = 'absent'
require(not application_properties.get('SigningIdentity') and not application_properties.get('Team'),
        'Archive metadata unexpectedly contains a signing identity/team.')
for key in ('CFBundleIcons', 'CFBundleIcons~ipad'):
    require(app_info.get(key) == icons_info[key], f'Archived {key} differs from actool output.')
for resource in compiled_files:
    require((app / resource.name).is_file() and digest(app / resource.name) == digest(resource),
            f'Compiled icon resource is missing or altered: {resource.name}')
require(read_plist(app / 'PrivacyInfo.xcprivacy') == read_plist(ios / 'PrivacyInfo.xcprivacy'),
        'Archived privacy manifest differs from the source.')
content_files = list(app.rglob('content.json'))
require(len(content_files) == 1 and content_files[0].read_bytes() == canonical_content,
        'The archive is missing its canonical SwiftPM content resource.')

revision = subprocess.run(['git', '-C', str(mobile.parent), 'rev-parse', 'HEAD'],
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
report = {
    'scope': 'Unsigned Release archive for iOS devices; inspection and later distribution signing.',
    'xtoolVersion': version, 'xcodeVersion': xcode_version, 'iPhoneOSSDK': sdk_version,
    'sourceRevision': revision.stdout.strip() if revision.returncode == 0 else None,
    'bundleIdentifier': bundle_id, 'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'], 'scheme': scheme,
    'deviceArchiveValidated': True, 'processedAppIconValidated': True,
    'privacyManifestValidated': True, 'canonicalContentValidated': True,
    'signature': signature, 'developerIdentityUsed': False,
    'distributionSigned': False, 'installableIPAProduced': False,
    'appStoreValidationPerformed': False, 'storeSubmitted': False,
    'remainingReleaseGates': [
        'Confirm the provisional bundle identifier with the owner and select the Apple team.',
        'Perform device, accessibility and product acceptance testing.',
        'Review final privacy declarations, icon appearance and store metadata.',
        'Use an authorised Apple distribution signing/export workflow and validate the app before submission.',
    ],
}
write_json(evidence / 'archive-validation.json', report)
write_json(output / 'archive-validation.json', report)
shutil.copy2(evidence / 'source-sha256.json', output / 'source-sha256.json')
(source / 'README-UNSIGNED.txt').write_text(
    'ConsegVida — generated Xcode project and local Swift package sources\n\n'
    'Open mobile/ios/xtool/ConsegVida.xcworkspace. Preserve the directory layout.\n'
    f'Application scheme: {scheme}. Device SDK used: {sdk_version}.\n'
    'DistributionAssets contains the canonical single-size catalog, actool output and partial plist.\n'
    'The staged Info.plist and xtool.yml include those processed icons and the privacy manifest.\n'
    'Regenerate processed assets when changing the icon or SDK; use the repository archive script.\n'
    'This package contains no team, certificate, profile or distribution signature.\n'
    'The separate xcarchive is for inspection and a later authorised signing/export workflow.\n'
    'It is not an installable IPA, TestFlight upload, App Store validation or store submission.\n',
    encoding='utf-8')

# Keep the source package portable and small; omit all build caches and user-specific Xcode state.
zip_entries = [source / 'mobile' / item for item in source_entries]
zip_entries += [staged_ios / 'DistributionAssets', staged_ios / 'xtool.yml',
                staged_ios / 'xtool/.xtool-tmp', workspace, source / 'README-UNSIGNED.txt']
with zipfile.ZipFile(output / 'ConsegVida-Xcode-project.zip', 'w', zipfile.ZIP_DEFLATED) as zipped:
    added = set()
    for entry in zip_entries:
        for path in (sorted(entry.rglob('*')) if entry.is_dir() else [entry]):
            if not path.is_file() or 'xcuserdata' in path.parts or path in added:
                continue
            require(not path.is_symlink(), f'Unexpected symlink in generated project: {path}')
            zipped.write(path, str(path.relative_to(source.parent)))
            added.add(path)
run(['ditto', '-c', '-k', '--keepParent', str(archive),
     str(output / 'ConsegVida-unsigned.xcarchive.zip')], 'package-archive.log')
(output / 'SHA256SUMS.txt').write_text(''.join(
    f'{digest(path)}  {path.name}\n' for path in sorted(output.iterdir()) if path.is_file()), encoding='utf-8')
artifacts.parent.mkdir(parents=True, exist_ok=True)
output.rename(artifacts)
print(f'Validated unsigned device archive and portable Xcode project: {artifacts}')
print('No distribution signature, installable IPA, App Store validation or submission was performed.')
PY
