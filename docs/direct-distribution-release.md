# Direct Distribution Release

This repo targets direct macOS distribution through GitHub Releases, not the Mac App Store.

## Prerequisites

- Apple Developer membership with a valid `Developer ID Application` certificate installed in Keychain Access
- Xcode command line tools
- `xcodegen` available on `PATH`
- Optional notarization profile created once:

```bash
xcrun notarytool store-credentials "TokenGuard-Notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

## Release Checklist

1. Regenerate the project and confirm the working tree only contains intended release-surface changes.
2. Run the baseline checkpoint:

```bash
swift test
xcodebuild -project TokenGuard.xcodeproj -scheme TokenGuard -configuration Debug -sdk macosx build
xcodebuild -project TokenGuard.xcodeproj -scheme TokenGuard -configuration Release -sdk macosx build
```

3. Build and archive the release app:

```bash
xcodegen generate --spec project.yml
xcodebuild -project TokenGuard.xcodeproj -scheme TokenGuard -configuration Release -archivePath dist/TokenGuard.xcarchive archive
```

4. Sign the archived app with Developer ID:

```bash
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  dist/TokenGuard.xcarchive/Products/Applications/TokenGuard.app
codesign --verify --deep --strict --verbose=2 \
  dist/TokenGuard.xcarchive/Products/Applications/TokenGuard.app
```

5. Create the release zip:

```bash
mkdir -p dist/staging
cp -R dist/TokenGuard.xcarchive/Products/Applications/TokenGuard.app dist/staging/
ditto -c -k --sequesterRsrc --keepParent dist/staging/TokenGuard.app dist/TokenGuard.zip
```

6. Notarize the zip and staple the app:

```bash
xcrun notarytool submit dist/TokenGuard.zip --keychain-profile "TokenGuard-Notary" --wait
xcrun stapler staple dist/staging/TokenGuard.app
ditto -c -k --sequesterRsrc --keepParent dist/staging/TokenGuard.app dist/TokenGuard-notarized.zip
spctl --assess --type execute --verbose dist/staging/TokenGuard.app
```

7. Upload `dist/TokenGuard-notarized.zip` to a GitHub Release and include the current version/build in the release notes.

## Optional One-Command Path

The local helper script handles archive, optional signing, optional notarization, and zip packaging:

```bash
scripts/release/build_release.sh
```

With signing and notarization enabled:

```bash
CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
NOTARY_PROFILE="TokenGuard-Notary" \
scripts/release/build_release.sh
```

## Optional DMG Packaging

If you prefer a DMG instead of a zip, create it after the app is signed:

```bash
mkdir -p dist/dmg
cp -R dist/staging/TokenGuard.app dist/dmg/
hdiutil create -volname "TokenGuard" -srcfolder dist/dmg -ov -format UDZO dist/TokenGuard.dmg
codesign --force --timestamp --sign "Developer ID Application: YOUR NAME (TEAMID)" dist/TokenGuard.dmg
xcrun notarytool submit dist/TokenGuard.dmg --keychain-profile "TokenGuard-Notary" --wait
xcrun stapler staple dist/TokenGuard.dmg
```

Zip remains the simpler default for GitHub Releases.
