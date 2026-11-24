#!/usr/bin/env python3
"""Mount the DMG, unpack the updater ZIP and test the exact apps users receive."""
import json
import os
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

IDENTIFIER = 'com.user.HeadphoneController'


def execute(command, timeout=60):
    return subprocess.run([str(x) for x in command], check=True, capture_output=True, text=True, timeout=timeout).stdout


def validate_app(app, expected, run_self_test=True):
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    if info.get('CFBundleIdentifier') != IDENTIFIER:
        raise ValueError('Wrong app bundle identifier')
    for key, expected_key in [('CFBundleShortVersionString', 'version'), ('CFBundleVersion', 'build')]:
        if info.get(key) != expected[expected_key]:
            raise ValueError('Packaged app version does not match the build metadata')
    executable = app / 'Contents/MacOS/HeadphoneController'
    if not os.access(executable, os.X_OK):
        raise ValueError('Packaged executable lost its executable permission')
    framework = app / 'Contents/Frameworks/Sparkle.framework'
    if not (framework / 'Sparkle').is_symlink() or not (framework / 'Sparkle').is_file():
        raise ValueError('Packaged Sparkle framework symlinks are missing or broken')
    execute(['codesign', '--verify', '--deep', '--strict', app])
    architectures = set(execute(['lipo', '-archs', executable]).split())
    if not {'arm64', 'x86_64'} <= architectures:
        raise ValueError('Packaged executable is not Universal 2')
    if run_self_test:
        output = execute([executable, '--self-test', '-SUEnableAutomaticChecks', 'NO'], timeout=25)
        report = json.loads(output)
        if report.get('status') != 'ok' or report.get('version') != expected['version'] or report.get('build') != expected['build']:
            raise ValueError('Packaged executable startup returned an invalid result')
    return info


def verify(assets):
    assets = Path(assets).resolve()
    expected = json.loads((assets / 'build-info.json').read_text())
    execute(['hdiutil', 'verify', assets / 'HeadphoneController.dmg'])
    with tempfile.TemporaryDirectory(prefix='headphone-artifact-test-') as directory:
        root = Path(directory)
        mount = root / 'mounted'
        mount.mkdir()
        attached = False
        try:
            execute(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mount, assets / 'HeadphoneController.dmg'])
            attached = True
            shortcut = mount / 'Applications'
            if not shortcut.is_symlink() or os.readlink(shortcut) != '/Applications':
                raise ValueError('DMG is missing its Applications installation shortcut')
            # Simulate copying the app out of the read-only DMG before launching it.
            dmg_app = root / 'from-dmg/HeadphoneController.app'
            execute(['ditto', mount / 'HeadphoneController.app', dmg_app])
            validate_app(dmg_app, expected)
        finally:
            if attached:
                try:
                    execute(['hdiutil', 'detach', mount], timeout=30)
                except (subprocess.SubprocessError, OSError):
                    execute(['hdiutil', 'detach', '-force', mount], timeout=30)
        zip_root = root / 'from-zip'
        execute(['ditto', '-x', '-k', assets / 'HeadphoneController-update.zip', zip_root])
        validate_app(zip_root / 'HeadphoneController.app', expected)
    print(f"DMG and updater ZIP passed integrity, version, signatures, symlinks, Universal 2 and startup tests ({expected['version']} build {expected['build']})")


if __name__ == '__main__':
    try:
        verify(sys.argv[1] if len(sys.argv) > 1 else 'release-assets')
    except subprocess.CalledProcessError as error:
        print(error.stdout or '', file=sys.stderr)
        print(error.stderr or '', file=sys.stderr)
        raise SystemExit(f'Artifact command failed: {error.cmd}')
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        raise SystemExit(f'Artifact verification failed: {error}')
