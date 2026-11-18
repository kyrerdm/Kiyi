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
