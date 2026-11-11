#!/bin/bash
# Keep macOS name/icon resolution on the distributed app, not a legacy build.
set -euo pipefail
cd "$(dirname "$0")/.."
kiyi_lsregister='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
kiyi_app="$PWD/build/Kıyı.app"
test -d "$kiyi_app"

kiyi_legacy="$PWD/build/Ada Notch.app"
if [[ -d "$kiyi_legacy" ]] && [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$kiyi_legacy/Contents/Info.plist")" == 'local.kayra.adanotch' ]]; then
    "$kiyi_lsregister" -u "$kiyi_legacy" || true
    mkdir -p build/Legacy
    kiyi_backup="$PWD/build/Legacy/Ada Notch.$(date +%Y%m%d-%H%M%S).zip"
    ditto -c -k --sequesterRsrc --keepParent "$kiyi_legacy" "$kiyi_backup"
    unzip -tq "$kiyi_backup" >/dev/null
    # The verified archive preserves the old app without another discoverable bundle.
    rm -r "$kiyi_legacy"
fi

kiyi_derived="$PWD/build/ForkDerived/Build/Products/Debug/Kıyı.app"
if [[ -d "$kiyi_derived" ]]; then
    "$kiyi_lsregister" -u "$kiyi_derived" >/dev/null 2>&1 || true
fi
"$kiyi_lsregister" -f "$kiyi_app"
