#!/bin/bash
# Build a portable, ad-hoc signed Universal app without touching the installed app.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
kiyi_derived="$PWD/build/ReleaseDerived"
xcodebuild -project App/boringNotch.xcodeproj -scheme boringNotch \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$kiyi_derived" -clonedSourcePackagesDirPath build/SourcePackages \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  build > build/release-build.log 2>&1 || { tail -n 60 build/release-build.log; exit 1; }
kiyi_app="$kiyi_derived/Build/Products/Release/Kıyı.app"
python3 scripts/verify-release.py "$kiyi_app"
kiyi_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$kiyi_app/Contents/Info.plist")
kiyi_output="$PWD/build/releases/Kiyi-$kiyi_version-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$kiyi_output/payload"
ditto "$kiyi_app" "$kiyi_output/payload/Kıyı.app"
cp docs/KURULUM.md "$kiyi_output/payload/ONCE-OKU.md"
cp LICENSE THIRD_PARTY_NOTICES.md "$kiyi_output/payload/"
ditto THIRD_PARTY_LICENSES "$kiyi_output/payload/THIRD_PARTY_LICENSES"
cp App/THIRD_PARTY_LICENSES "$kiyi_output/payload/UPSTREAM-THIRD-PARTY-LICENSES"
cp App/LICENSE "$kiyi_output/payload/UPSTREAM-LICENSE"
cp App/BoringNotchXPCHelper/WinMin-LICENSE.txt "$kiyi_output/payload/WinMin-LICENSE.txt"
# Include corresponding product source, without local Git history or build data.
python3 - "$kiyi_output/payload/Kiyi-source.tar.gz" <<'PY_SOURCE'
import sys, tarfile
from pathlib import Path
def clean(info):
    parts = Path(info.name).parts
    return None if any(p in {'.git', '.DS_Store', 'xcuserdata', '__pycache__'} for p in parts) else info
with tarfile.open(sys.argv[1], 'w:gz') as archive:
    for path in ['App', 'Sources', 'Tests', 'Assets', 'scripts', 'docs', '.github',
                 'updates', 'README.md', 'AGENTS.md', 'NOTICE.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'THIRD_PARTY_LICENSES']:
        archive.add(path, arcname='Kiyi-source/' + path, filter=clean)
PY_SOURCE
ln -s /Applications "$kiyi_output/payload/Applications"
hdiutil create -volname Kiyi -srcfolder "$kiyi_output/payload" -ov -format UDZO "$kiyi_output/Kiyi-$kiyi_version-universal.dmg" > "$kiyi_output/dmg.log"
ditto -c -k --sequesterRsrc --keepParent "$kiyi_output/payload" "$kiyi_output/Kiyi-$kiyi_version-universal.zip"
(cd "$kiyi_output" && shasum -a 256 *.dmg *.zip > SHA256SUMS.txt)
printf '\nRelease: %s\n' "$kiyi_output"
