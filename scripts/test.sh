#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/checks build/module-cache
python3 Tests/check-localization.py
python3 Tests/check-fork.py
swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" \
  App/BoringNotchXPCHelper/KiyiGelgit.swift Tests/GelgitChecks.swift \
  -o build/checks/gelgit-checks
build/checks/gelgit-checks

swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" \
  App/boringNotch/private/KiyiFullscreenPolicy.swift Tests/FullscreenChecks.swift \
  -o build/checks/fullscreen-checks
build/checks/fullscreen-checks

# Requires a GUI WindowServer session; keep headless source checks usable.
if [ "${KIYI_RUNTIME_WINDOW_TESTS:-0}" = "1" ]; then
  swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" \
    App/boringNotch/private/KiyiFullscreenPanel.swift App/boringNotch/private/KiyiFullscreenPolicy.swift \
    App/boringNotch/private/KiyiFullscreenWindows.swift Tests/FullscreenPanelChecks.swift \
    -o build/checks/fullscreen-panel-checks
  build/checks/fullscreen-panel-checks
else
  echo 'SKIP: GUI panel checks (enable with KIYI_RUNTIME_WINDOW_TESTS=1 in a WindowServer session)'
fi
