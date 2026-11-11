#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/checks build/module-cache
python3 - <<'PY'
from pathlib import Path
source = Path('Sources/main.swift').read_text().split('let app = NSApplication.shared')[0]
Path('build/checks/main.swift').write_text(source + '\ntry checkPreferences()\n')
PY
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" -target arm64-apple-macosx14.0 build/checks/main.swift Sources/LockBridge.swift Sources/Preferences.swift Sources/UIVerification.swift Sources/Extras.swift Sources/SystemControls.swift Sources/MediaStream.swift Sources/NotchShape.swift Tests/PreferencesChecks.swift -o build/checks/preferences-checks -framework AppKit -framework SwiftUI -framework QuartzCore -framework IOKit -framework ServiceManagement -framework CoreAudio -framework ApplicationServices
build/checks/preferences-checks
