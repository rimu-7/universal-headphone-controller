#!/usr/bin/env python3
"""Validate the appcast and app bundle agree before a release becomes visible."""
import base64
import json
import plistlib
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
FEED_URL = 'https://github.com/rimu-7/universal-headphone-controller/releases/latest/download/appcast.xml'


def validate(assets, download_prefix):
    assets = Path(assets)
    with zipfile.ZipFile(assets / 'HeadphoneController-update.zip') as archive:
        info = plistlib.loads(archive.read('HeadphoneController.app/Contents/Info.plist'))
        if not any('/Frameworks/Sparkle.framework/' in path for path in archive.namelist()):
            raise ValueError('Update archive is missing Sparkle')
    metadata = json.loads((assets / 'build-info.json').read_text())
    items = ET.parse(assets / 'appcast.xml').findall('./channel/item')
    if len(items) != 1:
        raise ValueError('Expected exactly one update item')
    item = items[0]
    enclosure = item.find('enclosure')
    if enclosure is None:
        raise ValueError('Missing update enclosure')
    checks = [
        (item.findtext(SPARKLE + 'version'), info['CFBundleVersion']),
        (item.findtext(SPARKLE + 'shortVersionString'), info['CFBundleShortVersionString']),
        (metadata['build'], info['CFBundleVersion']),
        (metadata['version'], info['CFBundleShortVersionString']),
        (enclosure.get('url'), download_prefix.rstrip('/') + '/HeadphoneController-update.zip'),
        (enclosure.get('length'), str((assets / 'HeadphoneController-update.zip').stat().st_size)),
        (info.get('SUFeedURL'), FEED_URL),
        (info.get('SUPublicEDKey'), Path('Config/SparklePublicKey.txt').read_text().strip()),
    ]
    if any(actual != expected for actual, expected in checks):
        raise ValueError('Appcast, archive and build metadata do not match')
    if len(base64.b64decode(enclosure.get(SPARKLE + 'edSignature', ''), validate=True)) != 64:
        raise ValueError('Missing or malformed Ed25519 update signature')
    if not info.get('SURequireSignedFeed') or not info.get('SUVerifyUpdateBeforeExtraction'):
        raise ValueError('The app must verify signed feeds and archives')
    return info


if __name__ == '__main__':
    try:
        validate(*sys.argv[1:])
    except (ValueError, KeyError, OSError, ET.ParseError, zipfile.BadZipFile) as error:
        raise SystemExit(str(error))
    print('Release feed, archive and bundle metadata match')
