"""Regression checks for the fork's live Defaults keys, localization and identity."""
import json
import re
from pathlib import Path
root = Path(__file__).resolve().parents[1]
app = root / 'App'
keys = []
for path in (app / 'boringNotch').rglob('*.swift'):
    for name in re.findall(r'Key<[^\n]*?>\(\s*"([^"\n]+)"', path.read_text()):
        assert name.isascii() and '.' not in name and not name.startswith('@'), (path, name)
        keys.append(name)
assert 'adaWidth' in keys and 'adaLockMusic' in keys
catalog = json.loads((app / 'boringNotch/Localizable.xcstrings').read_text())['strings']
for key in ['Advanced', 'Show menu bar icon', 'Choose any color', 'Enable Camera Access', 'Replace system HUD']:
    translated = catalog[key]['localizations']['tr']['stringUnit']['value']
    assert translated and translated != key, key
project = (app / 'boringNotch.xcodeproj/project.pbxproj').read_text()
assert 'PRODUCT_BUNDLE_IDENTIFIER = local.kayra.adanotch;' in project
assert 'PRODUCT_BUNDLE_IDENTIFIER = local.kayra.adanotch.BoringNotchXPCHelper;' in project
client = (app / 'boringNotch/XPCHelperClient/XPCHelperClient.swift').read_text()
assert '"local.kayra.adanotch.BoringNotchXPCHelper"' in client
print(f'PASS: {len(keys)} Defaults keys compatible with live KVO; Turkish regression strings; isolated application/XPC identities')
