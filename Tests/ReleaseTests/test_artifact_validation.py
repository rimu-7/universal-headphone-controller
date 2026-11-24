import importlib.util
import json
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('verify_artifacts', 'Scripts/verify_artifacts.py')
artifacts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifacts)


class ArtifactValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / 'HeadphoneController.app'
        contents = self.app / 'Contents'
        (contents / 'MacOS').mkdir(parents=True)
        self.executable = contents / 'MacOS/HeadphoneController'
        self.executable.write_text('fixture')
        self.executable.chmod(0o755)
        self.framework = contents / 'Frameworks/Sparkle.framework'
        (self.framework / 'Versions/B').mkdir(parents=True)
        (self.framework / 'Versions/B/Sparkle').write_text('fixture')
        (self.framework / 'Sparkle').symlink_to('Versions/B/Sparkle')
        self.info = contents / 'Info.plist'
        self.expected = dict(version='1.1.1', build='10.1')
        self.write_info()

    def write_info(self, **changes):
        info = dict(CFBundleIdentifier=artifacts.IDENTIFIER, CFBundleShortVersionString='1.1.1', CFBundleVersion='10.1')
        info.update(changes)
        self.info.write_bytes(plistlib.dumps(info))

    def command(self, args, timeout=60):
        if args[0] == 'lipo':
            return 'arm64 x86_64'
        if str(args[0]).endswith('/HeadphoneController'):
            return json.dumps(dict(status='ok', **self.expected))
        return ''

    def test_valid_bundle_is_started_with_bounded_self_test(self):
        with patch.object(artifacts, 'execute', side_effect=self.command) as run:
            artifacts.validate_app(self.app, self.expected)
        startup = [call for call in run.call_args_list if '--self-test' in call.args[0]]
        self.assertEqual(len(startup), 1)
        self.assertEqual(startup[0].kwargs['timeout'], 25)

    def test_wrong_packaged_version_is_rejected(self):
        self.write_info(CFBundleVersion='9.1')
        with self.assertRaises(ValueError):
            artifacts.validate_app(self.app, self.expected)

    def test_missing_execute_permission_is_rejected(self):
        self.executable.chmod(0o644)
        with self.assertRaises(ValueError):
            artifacts.validate_app(self.app, self.expected)

    def test_broken_framework_symlink_is_rejected(self):
        (self.framework / 'Versions/B/Sparkle').unlink()
        with self.assertRaises(ValueError):
            artifacts.validate_app(self.app, self.expected)

    def test_single_architecture_bundle_is_rejected(self):
        with patch.object(artifacts, 'execute', side_effect=['', 'arm64']):
            with self.assertRaises(ValueError):
                artifacts.validate_app(self.app, self.expected)

    def test_startup_failure_is_not_reported_as_success(self):
        with patch.object(artifacts, 'execute', side_effect=['', 'arm64 x86_64', subprocess.CalledProcessError(1, ['app','--self-test'])]):
            with self.assertRaises(subprocess.CalledProcessError):
                artifacts.validate_app(self.app, self.expected)
