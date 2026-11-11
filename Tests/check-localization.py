"""Validate supported locales, format arguments and resources in the built app."""
import json
import subprocess
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
locales = ('tr', 'en', 'de')
pattern = re.compile(r'%(?:\d+\$)?[-+ #0]*(?:\d+)?(?:\.\d+)?(?:ll|l)?[@dfius]')
for filename in ('Localizable.xcstrings', 'InfoPlist.xcstrings'):
    catalog = json.loads((root / 'App/boringNotch' / filename).read_text())
    for key, entry in catalog['strings'].items():
        if not key: continue
        units = [entry['localizations'][code]['stringUnit'] for code in locales]
        assert all(unit['value'] for unit in units), key
        arguments = [sorted(re.sub(r'%\d+\$', '%', value) for value in pattern.findall(unit['value'])) for unit in units]
        assert all(value == arguments[0] for value in arguments), (key, arguments)
    compiled_name = filename.replace('.xcstrings', '.strings')
    for code in locales:
        path = root / 'build/Kıyı.app/Contents/Resources' / (code + '.lproj') / compiled_name
        if not path.exists():
            raise AssertionError(f'Missing built language resource: {path}')
        data = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))
        for key, entry in catalog['strings'].items():
            assert data[key] == entry['localizations'][code]['stringUnit']['value'], (code, key)
print('PASS: Turkish, English and German translations, format arguments and compiled resources')
