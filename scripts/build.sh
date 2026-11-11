#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcodebuild -project App/boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath build/ForkDerived -clonedSourcePackagesDirPath build/SourcePackages CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build > build/fork-build.log 2>&1 || { tail -n 60 build/fork-build.log; exit 1; }
ditto "build/ForkDerived/Build/Products/Debug/Kıyı.app" "build/Kıyı.app"
codesign --verify --deep --strict "build/Kıyı.app"
bash scripts/register-app.sh
printf '%s\n' "$PWD/build/Kıyı.app"
