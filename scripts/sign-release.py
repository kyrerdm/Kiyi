#!/usr/bin/env python3
"""Create a signed Sparkle item for a DMG built by release.sh. Never exports keys."""
import argparse
import plistlib
import subprocess
import xml.etree.ElementTree as ET
from email.utils import formatdate
from pathlib import Path
parser = argparse.ArgumentParser()
parser.add_argument('dmg', type=Path)
args = parser.parse_args()
dmg = args.dmg.resolve()
assert dmg.is_file() and dmg.suffix == '.dmg'
info = plistlib.loads((dmg.parent / 'payload/Kıyı.app/Contents/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
build = info['CFBundleVersion']
tool = Path('build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update')
signature = subprocess.check_output([str(tool), '--account', 'kiyi-kyrerdm', '-p', str(dmg)], text=True).strip()
subprocess.run([str(tool), '--account', 'kiyi-kyrerdm', '--verify', str(dmg), signature], check=True)
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', ns)
feed = ET.Element('rss', version='2.0')
channel = ET.SubElement(feed, 'channel')
ET.SubElement(channel, 'title').text = 'Kıyı Updates'
ET.SubElement(channel, 'link').text = 'https://github.com/kyrerdm/Kiyi'
ET.SubElement(channel, 'description').text = 'Signed Kıyı updates'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = 'Kıyı ' + version
ET.SubElement(item, 'pubDate').text = formatdate(usegmt=True)
ET.SubElement(item, f'{{{ns}}}version').text = build
ET.SubElement(item, f'{{{ns}}}shortVersionString').text = version
ET.SubElement(item, f'{{{ns}}}minimumSystemVersion').text = '14.0'
ET.SubElement(item, 'enclosure', {
    'url': f'https://github.com/kyrerdm/Kiyi/releases/download/v{version}/{dmg.name}',
    'length': str(dmg.stat().st_size), 'type': 'application/octet-stream',
    f'{{{ns}}}edSignature': signature,
})
ET.indent(feed)
# Staging only: publish after uploading the exact DMG to its matching GitHub tag.
target = dmg.parent / 'appcast.xml'
ET.ElementTree(feed).write(target, encoding='utf-8', xml_declaration=True)
print(f'Verified signature; staged {target}. Upload exact DMG to v{version} BEFORE publishing this feed.')
