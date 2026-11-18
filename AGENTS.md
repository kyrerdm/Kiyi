# Working on Kıyı

Read README.md and docs/KURULUM.md first. The current product is the GPL fork in App/, not the legacy Sources/ prototype.

- Xcode project: App/boringNotch.xcodeproj; scheme: boringNotch.
- Local build: bash scripts/build.sh. This registers build/Kıyı.app with LaunchServices.
- Tests: bash scripts/test.sh.
- Shareable build: bash scripts/release.sh. Universal arm64+x86_64 Release; output build/releases/. Does not install, launch or modify permissions.
- Preserve bundle/XPC identifiers, GPL notices, third-party licenses and WinMin attribution.
- Keep Turkish, English and German localization consistent. Do not restart the app to change language.
- Use only Kıyı's signed feed in updates/appcast.xml; never restore Boring Notch's feed or advertise notarization that has not happened. Signing keys stay in Keychain; publish the exact signed DMG before its feed entry.
- Keep AX/window IPC off the Dock input callback and state lock. Preserve bounded fallback and stale-action guards.
- No TCC database edits, automatic security bypasses or permission-reset steps in installers. Authentication belongs to the user.
- Report hardware/OS coverage honestly: Universal compilation does not prove execution on Intel or old macOS releases.
- Do not commit build/, personal logs, signing secrets or local user paths. Do not overwrite a user's installation without preserving it.
- Do not publish a binary without its corresponding accessible source and licenses.
