import base64
import importlib.util
import json
import plistlib
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('validate_release', 'Scripts/validate_release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.assets = Path(self.temp.name)
        self.prefix = 'https://github.com/rimu-7/universal-headphone-controller/releases/download/v1.1.0-build.20.1/'
        info = dict(CFBundleVersion='20.1', CFBundleShortVersionString='1.1.0',
                    SUFeedURL=release.FEED_URL,
                    SUPublicEDKey=Path('Config/SparklePublicKey.txt').read_text().strip(),
                    SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True)
        self.archive = self.assets / 'HeadphoneController-update.zip'
        with zipfile.ZipFile(self.archive, 'w') as archive:
            archive.writestr('HeadphoneController.app/Contents/Info.plist', plistlib.dumps(info))
            archive.writestr('HeadphoneController.app/Contents/Frameworks/Sparkle.framework/Sparkle', b'fixture')
        (self.assets / 'build-info.json').write_text(json.dumps(dict(build='20.1', version='1.1.0')))
        root = ET.Element('rss')
        item = ET.SubElement(ET.SubElement(root, 'channel'), 'item')
        ET.SubElement(item, release.SPARKLE + 'version').text = '20.1'
        ET.SubElement(item, release.SPARKLE + 'shortVersionString').text = '1.1.0'
        ET.SubElement(item, 'enclosure', {'url': self.prefix + self.archive.name,
                      'length': str(self.archive.stat().st_size),
                      release.SPARKLE + 'edSignature': base64.b64encode(bytes(64)).decode()})
        self.tree = ET.ElementTree(root)
        self.save()

    def save(self):
        self.tree.write(self.assets / 'appcast.xml')

    def test_matching_artifact_is_accepted(self):
        self.assertEqual(release.validate(self.assets, self.prefix)['CFBundleVersion'], '20.1')

    def test_mismatching_version_is_rejected(self):
        self.tree.find('./channel/item/' + release.SPARKLE + 'version').text = '19.1'
        self.save()
        with self.assertRaises(ValueError):
            release.validate(self.assets, self.prefix)

    def test_wrong_download_location_is_rejected(self):
        self.tree.find('./channel/item/enclosure').set('url', 'https://example.com/untrusted.zip')
        self.save()
        with self.assertRaises(ValueError):
            release.validate(self.assets, self.prefix)

    def test_changed_archive_length_is_rejected(self):
        with self.archive.open('ab') as archive:
            archive.write(b'tampered')
        with self.assertRaises(ValueError):
            release.validate(self.assets, self.prefix)

    def test_missing_archive_signature_is_rejected(self):
        self.tree.find('./channel/item/enclosure').attrib.pop(release.SPARKLE + 'edSignature')
        self.save()
        with self.assertRaises(ValueError):
            release.validate(self.assets, self.prefix)

    def test_duplicate_update_items_are_rejected(self):
        self.tree.find('./channel').append(ET.Element('item'))
        self.save()
        with self.assertRaises(ValueError):
            release.validate(self.assets, self.prefix)
