#!/usr/bin/env python3
"""Installer transaction/Git checks with disposable bundles, data and command doubles.

--native additionally exercises actual AppKit launch/normal quit with an isolated
fixture app. Never launches or quits the user's Mac Buddy bundle identifier.
"""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--native', action='store_true', help='Also test actual AppKit lifecycle (needs a logged-in macOS desktop).')
args = parser.parse_args()
checks = 0


def run(command, cwd=None, env=None, ok=True):
    result = subprocess.run([str(x) for x in command], cwd=cwd, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
    if ok and result.returncode:
        raise AssertionError(result.stdout)
    return result


def passed(message):
    global checks
    checks += 1
    print('PASS ' + message, flush=True)


def write_executable(path, content):
    path.write_text(content)
    path.chmod(0o755)


def bundle(path, identifier, version):
    (path / 'Contents/MacOS').mkdir(parents=True)
    (path / 'Contents/Resources').mkdir()
    (path / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': identifier, 'CFBundleExecutable': 'MacBuddy',
        'CFBundleName': 'Mac Buddy', 'CFBundleVersion': '1',
        'CFBundlePackageType': 'APPL', 'LSUIElement': True,
    }))
    write_executable(path / 'Contents/MacOS/MacBuddy', '#!/bin/sh\nexit 0\n')
    (path / 'Contents/Resources/version').write_text(version)


class Fixture:
    def __init__(self, parent):
        self.root = parent / uuid.uuid4().hex
        self.repo = self.root / 'source with spaces'
        self.destination = self.root / 'Applications with spaces'
        self.bin = self.root / 'commands'
        for p in [self.repo / 'scripts', self.repo / 'Resources', self.destination, self.bin]:
            p.mkdir(parents=True, exist_ok=True)
        for name in ['install.sh', 'install-lifecycle.swift']:
            shutil.copyfile(ROOT / 'scripts' / name, self.repo / 'scripts' / name)
        self.identifier = 'app.macbuddy.install-check.' + uuid.uuid4().hex
        (self.repo / 'Resources/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': self.identifier}))
        bundle(self.repo / 'fixture.app', self.identifier, 'new')
        self.events = self.root / 'events'
        self.data = self.root / 'personal data'
        self.data.mkdir()
        (self.data / 'preferences.plist').write_bytes(plistlib.dumps({'opacity': 0.65, 'notifications': True, 'position': [0.2, 0.4]}))
        with sqlite3.connect(self.data / 'history.sqlite') as c:
            c.execute('CREATE TABLE summaries (payload TEXT)')
            c.execute("INSERT INTO summaries VALUES ('real-history-sentinel')")
        (self.data / 'history.sqlite-wal').write_bytes(b'preserve-sidecar')
        self.before = self.data_hashes()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        INSTALL_EVENTS=str(self.events), INSTALL_FIXTURE=str(self.root),
                        INSTALL_DATA=str(self.data))
        write_executable(self.repo / 'scripts/build.sh', '''#!/bin/zsh
set -eu
print build >> "$INSTALL_EVENTS"
[[ ! -e "$INSTALL_FIXTURE/fail-build" ]]
cd "${0:A:h:h}"
mkdir -p dist
rm -rf 'dist/Mac Buddy.app'
/usr/bin/ditto fixture.app 'dist/Mac Buddy.app'
''')
        # Real PlistBuddy, ditto, filesystem renames and Git are used. Only the
        # compiler/signature/lifecycle operations are doubled in these fast checks.
        write_executable(self.bin / 'xcrun', '''#!/bin/zsh
set -eu
if [[ "$*" == 'swiftc --version' ]]; then
    print 'Apple Swift version 6.1.2'; exit 0
fi
output="${@[-1]}"
cat > "$output" <<'HELPER'
#!/bin/zsh
set -eu
print -r -- "$1" >> "$INSTALL_EVENTS"
if [[ "$1" == quit ]]; then
    [[ ! -e "$INSTALL_FIXTURE/refuse-quit" ]] || exit 1
    print 0
else
    [[ ! -e "$INSTALL_FIXTURE/fail-open" ]] || exit 1
fi
HELPER
chmod +x "$output"
''')
        write_executable(self.bin / 'codesign', '#!/bin/zsh\n[[ ! -e "$INSTALL_FIXTURE/fail-signature" ]]\n')
        write_executable(self.bin / 'ditto', '''#!/bin/zsh
if [[ "$2" == */New.app && -e "$INSTALL_FIXTURE/fail-copy" ]]; then
    mkdir -p "$2"; exit 1
fi
exec /usr/bin/ditto "$@"
''')
        write_executable(self.bin / 'mv', '''#!/bin/zsh
if [[ "$1" == */New.app && -e "$INSTALL_FIXTURE/fail-replace" ]]; then exit 1; fi
exec /bin/mv "$@"
''')

    def data_hashes(self):
        return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in self.data.iterdir()}

    def install(self, *options, ok=True):
        result = run(['/bin/zsh', self.repo / 'scripts/install.sh', '--destination', self.destination, *options], env=self.env, ok=ok)
        assert self.data_hashes() == self.before, 'Preferences/history/sidecars changed'
        return result

    @property
    def target(self):
        return self.destination / 'Mac Buddy.app'

    def git(self, *options):
        return run(['git', '-C', self.repo, *options], env=self.env)

    def init_git(self):
        self.git('init', '-b', 'main')
        self.git('config', 'user.name', 'Installer Check')
        self.git('config', 'user.email', 'check@example.invalid')
        self.git('config', 'commit.gpgsign', 'false')
        (self.repo / '.gitignore').write_text('tmp/\ndist/\n.build/\n')
        self.git('add', '.')
        self.git('commit', '-m', 'Fixture')


with tempfile.TemporaryDirectory(prefix='MacBuddy-installer-check-') as scratch:
    parent = Path(scratch).resolve()
    f = Fixture(parent)
    f.install('--no-open')
    assert (f.target / 'Contents/Resources/version').read_text() == 'new'
    assert f.events.read_text().splitlines() == ['build', 'quit']
    passed('source-ZIP install handles spaced paths and --no-open; settings/history/sidecars unchanged')

    (f.repo / 'fixture.app/Contents/Resources/version').write_text('newer')
    f.install('--no-update')
    assert (f.target / 'Contents/Resources/version').read_text() == 'newer'
    assert (f.destination / '.MacBuddy-previous.app/Contents/Resources/version').read_text() == 'new'
    assert f.events.read_text().splitlines()[-3:] == ['build', 'quit', 'open']
    (f.repo / 'fixture.app/Contents/Resources/version').write_text('latest')
    f.install('--no-update', '--no-open')
    assert (f.destination / '.MacBuddy-previous.app/Contents/Resources/version').read_text() == 'newer'
    assert len(list(f.destination.glob('.MacBuddy-previous*.app'))) == 1
    passed('repeat updates replace the stable app, launch by default and retain exactly one previous bundle')

    for failure in ['fail-build', 'fail-signature', 'fail-copy', 'refuse-quit', 'fail-replace']:
        f = Fixture(parent)
        bundle(f.target, f.identifier, 'old')
        (f.root / failure).touch()
        result = f.install('--no-update', ok=False)
        assert result.returncode != 0
        assert (f.target / 'Contents/Resources/version').read_text() == 'old', (failure, result.stdout)
        if failure in ['fail-build', 'fail-signature', 'fail-copy']:
            assert 'quit' not in f.events.read_text().splitlines()
        assert not list(f.destination.glob('.MacBuddy-install.*'))
        assert not (f.repo / 'tmp/install.lock').exists()
        passed(failure + ' preserves/restores the existing app and releases installer locks')

    f = Fixture(parent)
    bundle(f.target, 'unrelated.app', 'untouched')
    assert f.install('--no-update', ok=False).returncode != 0
    assert not f.events.exists()
    shutil.rmtree(f.target)
    f.target.write_text('unrelated file')
    assert f.install('--no-update', ok=False).returncode != 0
    assert f.target.read_text() == 'unrelated file'
    f.target.unlink()
    f.target.symlink_to(f.repo / 'fixture.app')
    assert f.install('--no-update', ok=False).returncode != 0
    assert f.target.is_symlink()
    passed('unrelated app/file and symlink destinations are not overwritten')

    f = Fixture(parent)
    (f.destination / '.MacBuddy-install.lock').mkdir()
    assert f.install('--no-update', ok=False).returncode != 0
    assert (f.destination / '.MacBuddy-install.lock').is_dir()
    assert not (f.repo / 'tmp/install.lock').exists()
    passed('concurrent-install lock is respected without deleting another installer lock')

    f = Fixture(parent)
    bundle(f.target, f.identifier, 'old')
    (f.root / 'fail-open').touch()
    result = f.install('--no-update', ok=False)
    assert result.returncode != 0 and 'Installed successfully' in result.stdout
    assert (f.target / 'Contents/Resources/version').read_text() == 'new'
    assert (f.destination / '.MacBuddy-previous.app/Contents/Resources/version').read_text() == 'old'
    passed('launch failure leaves the verified installation and previous app available for manual recovery')

    f = Fixture(parent)
    f.init_git()
    upstream = f.root / 'upstream.git'
    run(['git', 'clone', '--bare', f.repo, upstream], env=f.env)
    f.git('remote', 'add', 'origin', str(upstream))
    f.git('fetch', 'origin')
    f.git('branch', '--set-upstream-to=origin/main', 'main')
    producer = f.root / 'producer'
    run(['git', 'clone', upstream, producer], env=f.env)
    for key, value in [('user.name', 'Installer Check'), ('user.email', 'check@example.invalid'), ('commit.gpgsign', 'false')]:
        run(['git', '-C', producer, 'config', key, value], env=f.env)
    (producer / 'fixture.app/Contents/Resources/version').write_text('remote-new')
    # Prove the freshly pulled installer is re-executed, not the old body.
    script = producer / 'scripts/install.sh'
    script.write_text(script.read_text().replace('print -- "Building Mac Buddy.', 'print refreshed-installer >> "$INSTALL_EVENTS"\n    print -- "Building Mac Buddy.'))
    run(['git', '-C', producer, 'add', '.'], env=f.env)
    run(['git', '-C', producer, 'commit', '-m', 'Remote update'], env=f.env)
    run(['git', '-C', producer, 'push'], env=f.env)
    f.install('--no-open')
    assert (f.target / 'Contents/Resources/version').read_text() == 'remote-new'
    assert f.events.read_text().splitlines()[0] == 'refreshed-installer'
    passed('Git update fast-forwards, re-executes the new installer and installs the fetched build')

    (f.repo / 'local.txt').write_text('keep my changes')
    f.events.unlink()
    assert f.install('--no-open', ok=False).returncode != 0
    assert not f.events.exists()
    assert (f.repo / 'local.txt').read_text() == 'keep my changes'
    f.git('add', 'local.txt'); f.git('commit', '-m', 'Local change')
    (producer / 'remote.txt').write_text('divergent upstream')
    run(['git', '-C', producer, 'add', '.'], env=f.env)
    run(['git', '-C', producer, 'commit', '-m', 'Diverge'], env=f.env)
    run(['git', '-C', producer, 'push'], env=f.env)
    local_head = f.git('rev-parse', 'HEAD').stdout
    assert f.install('--no-open', ok=False).returncode != 0
    assert f.git('rev-parse', 'HEAD').stdout == local_head
    assert not f.events.exists()
    f.git('remote', 'set-url', 'origin', str(f.root / 'unreachable.git'))
    assert f.install('--no-open', ok=False).returncode != 0
    assert f.git('rev-parse', 'HEAD').stdout == local_head and not f.events.exists()
    passed('dirty, diverged or unreachable Git checkout stops before building/quitting and preserves local commits/files')

    if args.native:
        # Actual shell installer/copy/signature/AppKit helper, unique fixture ID.
        f = Fixture(parent)
        f.env = dict(os.environ)  # remove every command double; retain real HOME
        shutil.rmtree(f.repo / 'fixture.app')
        app = f.repo / 'fixture.app'
        bundle(app, f.identifier, 'old')
        fixture_source = f.root / 'fixture.swift'
        fixture_source.write_text('''import AppKit
final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
    func applicationWillTerminate(_ note: Notification) {
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("normal-quit.marker")
        try! Data("flushed".utf8).write(to: url)
    }
}
let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
''')
        module_cache = f.root / 'module-cache'
        run(['xcrun', 'swiftc', '-module-cache-path', module_cache, fixture_source, '-o', app / 'Contents/MacOS/MacBuddy'])
        write_executable(f.repo / 'scripts/build.sh', '''#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p dist
rm -rf 'dist/Mac Buddy.app'
/usr/bin/ditto fixture.app 'dist/Mac Buddy.app'
/usr/bin/codesign --force --sign - 'dist/Mac Buddy.app'
''')
        lifecycle = f.root / 'lifecycle'
        run(['xcrun', 'swiftc', '-swift-version', '5', '-module-cache-path', module_cache,
             ROOT / 'scripts/install-lifecycle.swift', '-o', lifecycle])
        try:
            f.install('--no-update')
            (f.repo / 'fixture.app/Contents/Resources/version').write_text('new')
            f.install('--no-update')
            assert (f.destination / 'normal-quit.marker').read_text() == 'flushed'
            assert (f.target / 'Contents/Resources/version').read_text() == 'new'
            assert (f.destination / '.MacBuddy-previous.app/Contents/Resources/version').read_text() == 'old'
            assert run([lifecycle, 'quit', f.identifier]).stdout.strip() == '1'
            passed('native install/update launches the exact path, normally quits and flushes the old app and preserves fixture data')
        finally:
            run([lifecycle, 'quit', f.identifier], ok=False)

print(str(checks) + ' installer checks; 0 failures', flush=True)
