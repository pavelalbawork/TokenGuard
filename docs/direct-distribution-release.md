# Direct Distribution Release

This repo targets direct macOS distribution through GitHub Releases, not the Mac App Store.

## Prerequisites

- Apple Developer membership with a valid `Developer ID Application` certificate installed in Keychain Access
- Xcode command line tools
- `xcodegen` available on `PATH`
- Optional notarization profile created once:

```bash
xcrun notarytool store-credentials "UsageTool-Notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

## Release Checklist

1. Regenerate the project and confirm the working tree only contains intended release-surface changes.
2. Run the baseline checkpoint:

```bash
swift test
xcodebuild -project UsageTool.xcodeproj -scheme UsageTool -configuration Debug -sdk macosx build
xcodebuild -project UsageTool.xcodeproj -scheme UsageTool -configuration Release -sdk macosx build
```

3. Build and archive the release app:

```bash
xcodegen generate --spec project.yml
xcodebuild -project UsageTool.xcodeproj -scheme UsageTool -configuration Release -archivePath dist/UsageTool.xcarchive archive
```

4. Sign the archived app with Developer ID:

```bash
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  dist/UsageTool.xcarchive/Products/Applications/UsageTool.app
codesign --verify --deep --strict --verbose=2 \
  dist/UsageTool.xcarchive/Products/Applications/UsageTool.app
```

5. Create the release zip:

```bash
mkdir -p dist/staging
cp -R dist/UsageTool.xcarchive/Products/Applications/UsageTool.app dist/staging/
ditto -c -k --sequesterRsrc --keepParent dist/staging/UsageTool.app dist/UsageTool.zip
```

6. Notarize the zip and staple the app:

```bash
xcrun notarytool submit dist/UsageTool.zip --keychain-profile "UsageTool-Notary" --wait
xcrun stapler staple dist/staging/UsageTool.app
ditto -c -k --sequesterRsrc --keepParent dist/staging/UsageTool.app dist/UsageTool-notarized.zip
spctl --assess --type execute --verbose dist/staging/UsageTool.app
```

7. Upload `dist/UsageTool-notarized.zip` to a GitHub Release and include the current version/build in the release notes.

## Optional One-Command Path

The local helper script handles archive, optional signing, optional notarization, and zip packaging:

```bash
scripts/release/build_release.sh
```

With signing and notarization enabled:

```bash
CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
NOTARY_PROFILE="UsageTool-Notary" \
scripts/release/build_release.sh
```

## Optional DMG Packaging

If you prefer a DMG instead of a zip, create it after the app is signed:

```bash
mkdir -p dist/dmg
cp -R dist/staging/UsageTool.app dist/dmg/
hdiutil create -volname "UsageTool" -srcfolder dist/dmg -ov -format UDZO dist/UsageTool.dmg
codesign --force --timestamp --sign "Developer ID Application: YOUR NAME (TEAMID)" dist/UsageTool.dmg
xcrun notarytool submit dist/UsageTool.dmg --keychain-profile "UsageTool-Notary" --wait
xcrun stapler staple dist/UsageTool.dmg
```

Zip remains the simpler default for GitHub Releases.
