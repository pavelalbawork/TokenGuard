# Direct Distribution Release

This repo targets direct macOS distribution through GitHub Releases, not the Mac App Store.

## Prerequisites

- Xcode command line tools
- `xcodegen` available on `PATH`

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

4. Create the release zip:

```bash
mkdir -p dist/staging
cp -R dist/TokenGuard.xcarchive/Products/Applications/TokenGuard.app dist/staging/
ditto -c -k --sequesterRsrc --keepParent dist/staging/TokenGuard.app dist/TokenGuard.zip
```

5. Smoke-test the packaged app locally.
6. Upload `dist/TokenGuard.zip` to a GitHub Release and include the current version/build in the release notes.

## Optional One-Command Path

The local helper script handles project generation, archive, and zip packaging:

```bash
scripts/release/build_release.sh
```

## Optional DMG Packaging

If you prefer a DMG instead of a zip:

```bash
mkdir -p dist/dmg
cp -R dist/staging/TokenGuard.app dist/dmg/
hdiutil create -volname "TokenGuard" -srcfolder dist/dmg -ov -format UDZO dist/TokenGuard.dmg
```

Zip remains the simpler default for GitHub Releases.
