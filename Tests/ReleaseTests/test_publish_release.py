import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        (root / 'Scripts').mkdir()
        self.script = root / 'Scripts/publish_release.sh'
        shutil.copyfile('Scripts/publish_release.sh', self.script)
        (root / 'release-assets').mkdir()
        for filename in ['HeadphoneController.dmg', 'HeadphoneController-update.zip', 'appcast.xml', 'SHA256SUMS']:
            (root / 'release-assets' / filename).write_text('fixture')
        (root / 'bin').mkdir()
        mock = root / 'bin/gh'
        mock.write_text('''#!/usr/bin/env python3
import json, os, sys
with open(os.environ['CALLS'], 'a') as log: log.write(json.dumps(sys.argv[1:])+'\\n')
if sys.argv[1] == 'api':
    print(os.environ['MOCK_HEAD']); sys.exit(0)
if sys.argv[1:3] == ['release','view']:
    if os.environ.get('PUBLISHED') == '1':
        print(json.dumps(dict(isDraft=False, targetCommitish=os.environ['GITHUB_SHA']))); sys.exit(0)
    sys.exit(1)
if sys.argv[1:3] == ['release','upload'] and os.environ.get('FAIL_UPLOAD') == '1': sys.exit(1)
sys.exit(0)
''')
        mock.chmod(0o755)
        self.calls = root / 'calls.jsonl'
        self.env = dict(os.environ, PATH=str(root / 'bin') + os.pathsep + os.environ['PATH'],
                        GH_REPO='owner/repo', GITHUB_SHA='a' * 40, MOCK_HEAD='a' * 40,
                        RELEASE_TAG='v1.1.0-build.9.1', RELEASE_TITLE='Fixture release', CALLS=str(self.calls))

    def run_publish(self, **environment):
        return subprocess.run(['bash', str(self.script)], env=dict(self.env, **environment), capture_output=True, text=True)

    def operations(self):
        return [json.loads(line)[:2] for line in self.calls.read_text().splitlines()]

    def test_superseded_build_never_creates_or_uploads_a_release(self):
        result = self.run_publish(MOCK_HEAD='b' * 40)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(['release', 'create'], self.operations())
        self.assertNotIn(['release', 'upload'], self.operations())

    def test_current_build_uploads_before_publishing(self):
        result = self.run_publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.operations()
        self.assertLess(calls.index(['release', 'create']), calls.index(['release', 'upload']))
        self.assertLess(calls.index(['release', 'upload']), calls.index(['release', 'edit']))

    def test_failed_upload_never_publishes(self):
        result = self.run_publish(FAIL_UPLOAD='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(['release', 'edit'], self.operations())

    def test_published_build_is_not_overwritten(self):
        result = self.run_publish(PUBLISHED='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(['release', 'upload'], self.operations())
        self.assertNotIn(['release', 'edit'], self.operations())
