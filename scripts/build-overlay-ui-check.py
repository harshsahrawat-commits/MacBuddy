#!/usr/bin/env python3
"""Build an isolated native UI check from the actual app sources (no profiling)."""
import argparse
import datetime
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
output = (args.output or root / 'tmp' / 'validation' / ('overlay-ui-' + stamp)).resolve()
output.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, SWIFTPM_MODULECACHE_OVERRIDE=str(root / '.build/module-cache'),
           CLANG_MODULE_CACHE_PATH=str(root / '.build/clang-cache'))
with (output / 'ui-check-build.log').open('w') as log:
    subprocess.run(['swift', 'build', '--disable-sandbox', '--build-system', 'native', '-c', 'release', '--arch', 'arm64', '--product', 'MacBuddy'], cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    binary = root / '.build/arm64-apple-macosx/release'
    destination = output / ('Mac Buddy UI Check ' + stamp + '.app')
    app = output / ('.MacBuddyUICheck-stage-' + uuid.uuid4().hex + '.app')
    (app / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
    (app / 'Contents/Resources').mkdir(parents=True, exist_ok=True)
    shutil.copytree(root / 'Resources/Fonts', app / 'Contents/Resources/Fonts', dirs_exist_ok=True)
    shutil.copyfile(root / 'THIRD_PARTY_NOTICES.md', app / 'Contents/Resources/THIRD_PARTY_NOTICES.md')
    info = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
    info.update(CFBundleIdentifier='app.macbuddy.overlay-ui-check.run-' + stamp.lower(), CFBundleName='Mac Buddy UI Check',
                CFBundleDisplayName='Mac Buddy UI Check', CFBundleExecutable='MacBuddyUICheck')
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    sources = sorted(str(p) for p in (root / 'Sources/MacBuddy').glob('*.swift') if p.name != 'main.swift')
    objects = sorted(str(p) for folder in ['MacBuddyCore.build', 'NativeTelemetry.build'] for p in (binary / folder).glob('*.o'))
    command = ['xcrun', 'swiftc', '-swift-version', '5', '-O', '-module-cache-path', str(root / '.build/module-cache'),
               '-I', str(binary / 'Modules'), '-Xcc', '-fmodule-map-file=' + str(binary / 'NativeTelemetry.build/module.modulemap'),
               '-Xcc', '-fmodule-map-file=' + str(root / 'Sources/CSQLite/module.modulemap')]
    command += sources + [str(root / 'scripts/overlay-ui-check.swift')] + objects
    command += ['-lsqlite3', '-framework', 'IOKit', '-framework', 'CoreFoundation', '-framework', 'Carbon',
                '-o', str(app / 'Contents/MacOS/MacBuddyUICheck')]
    subprocess.run(command, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], stdout=log, stderr=subprocess.STDOUT, check=True)
    subprocess.run(['codesign', '--verify', '--strict', str(app)], stdout=log, stderr=subprocess.STDOUT, check=True)
    # Preserve the old executable's inode even if a previous check is still open.
    # A unique identifier also prevents LaunchServices returning an older copy.
    if destination.exists():
        destination.rename(output / ('.MacBuddyUICheck-previous-' + uuid.uuid4().hex + '.app'))
    app.rename(destination)
print(destination)
