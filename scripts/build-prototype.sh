#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/Ada.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/module-cache
xcrun swiftc -swift-version 5 -O -module-cache-path "$PWD/build/module-cache" -target arm64-apple-macosx14.0 Sources/main.swift Sources/LockBridge.swift Sources/Preferences.swift Sources/UIVerification.swift Sources/Extras.swift Sources/SystemControls.swift Sources/MediaStream.swift Sources/NotchShape.swift -o "$APP/Contents/MacOS/Ada" -framework AppKit -framework SwiftUI -framework QuartzCore -framework IOKit -framework ServiceManagement -framework CoreAudio -framework ApplicationServices
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Ada</string>
<key>CFBundleIdentifier</key><string>local.kayra.ada</string>
<key>CFBundleName</key><string>Ada</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSAppleEventsUsageDescription</key><string>Çalan şarkıyı adada göstermek ve oynatmayı kontrol etmek için Spotify’a erişir.</string>
<key>NSPrefersDisplaySafeAreaCompatibilityMode</key><false/>
</dict></plist>
PLIST
mkdir -p "$APP/Contents/Frameworks"
ditto App/mediaremote-adapter/MediaRemoteAdapter.framework "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
cp App/mediaremote-adapter/mediaremote-adapter.pl "$APP/Contents/Resources/"
cp LICENSE THIRD_PARTY_LICENSES "$APP/Contents/Resources/"
codesign --force --sign - "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
