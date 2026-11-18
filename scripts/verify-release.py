#!/usr/bin/env python3
"""Reject nonportable, incomplete or incorrectly signed distribution bundles."""
import plistlib
import subprocess
import sys
from pathlib import Path

app = Path(sys.argv[1]).resolve()
def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'local.kayra.adanotch'
assert info['LSMinimumSystemVersion'] == '14.0', info.get('LSMinimumSystemVersion')
assert info.get('SUFeedURL') == 'https://raw.githubusercontent.com/kyrerdm/Kiyi/main/updates/appcast.xml'
assert info.get('SUScheduledCheckInterval') == 7200
assert info.get('SUPublicEDKey') == 'Xq1Dby6rhoS5CrZy5D/XlXgOEpA6DVhyX/80RfB8hAI='
helper = app / 'Contents/XPCServices/BoringNotchXPCHelper.xpc'
assert helper.is_dir(), 'Missing XPC helper'
helper_info = plistlib.loads((helper / 'Contents/Info.plist').read_bytes())
assert helper_info['CFBundleIdentifier'] == 'local.kayra.adanotch.BoringNotchXPCHelper'
assert list(helper.rglob('WinMin-LICENSE.txt')), 'Missing WinMin attribution'
assert list((app / 'Contents/Resources').glob('*.lproj')), 'Missing localization resources'
count = 0
for path in app.rglob('*'):
    if not path.is_file() or path.is_symlink():
        continue
    kind = run('/usr/bin/file', '-b', str(path))
    if 'Mach-O' not in kind:
        continue
    count += 1
    archs = run('/usr/bin/lipo', '-archs', str(path)).split()
    assert {'arm64', 'x86_64'} <= set(archs), (path, archs)
    libraries = run('/usr/bin/otool', '-L', str(path)).splitlines()[1:]
    for library in libraries:
        if not library.startswith('\t'):
            continue  # Universal otool output repeats an architecture header.
        name = library.strip().split(' (')[0]
        assert name.startswith(('@', '/System/Library/', '/usr/lib/')), (path, name)
assert count >= 3, 'Expected app, helper and embedded frameworks'
run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(app))
print(f'PASS: Universal arm64+x86_64, {count} Mach-O files, portable libraries, identity, licenses, resources and signature')
