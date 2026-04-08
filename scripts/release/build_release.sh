#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_PATH="$ROOT_DIR/TokenGuard.xcodeproj"
SCHEME="TokenGuard"
CONFIGURATION="${CONFIGURATION:-Release}"
PRODUCT_NAME="TokenGuard"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
ARCHIVE_PATH="$DIST_DIR/$PRODUCT_NAME.xcarchive"
STAGING_DIR="$DIST_DIR/staging"
APP_PATH="$ARCHIVE_PATH/Products/Applications/$PRODUCT_NAME.app"
UNSIGNED_ZIP_PATH="$DIST_DIR/$PRODUCT_NAME-unsigned.zip"
SIGNED_ZIP_PATH="$DIST_DIR/$PRODUCT_NAME.zip"

mkdir -p "$DIST_DIR"
rm -rf "$ARCHIVE_PATH" "$STAGING_DIR" "$UNSIGNED_ZIP_PATH" "$SIGNED_ZIP_PATH"

echo "Generating project"
xcodegen generate --spec "$ROOT_DIR/project.yml"

echo "Archiving $PRODUCT_NAME"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  archive

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected archived app at $APP_PATH" >&2
  exit 1
fi

APP_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist")"
APP_BUILD="$(plutil -extract CFBundleVersion raw "$APP_PATH/Contents/Info.plist")"
echo "Archived version $APP_VERSION ($APP_BUILD)"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "Signing app with Developer ID identity"
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_PATH"
else
  echo "CODESIGN_IDENTITY not set; packaging unsigned artifact only"
fi

mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"

ditto -c -k --sequesterRsrc --keepParent "$STAGING_DIR/$PRODUCT_NAME.app" "$UNSIGNED_ZIP_PATH"
ZIP_PATH="$UNSIGNED_ZIP_PATH"

if [[ -n "${NOTARY_PROFILE:-}" && -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "Submitting zip for notarization with profile $NOTARY_PROFILE"
  xcrun notarytool submit "$UNSIGNED_ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "Stapling notarization ticket"
  xcrun stapler staple "$STAGING_DIR/$PRODUCT_NAME.app"
  ditto -c -k --sequesterRsrc --keepParent "$STAGING_DIR/$PRODUCT_NAME.app" "$SIGNED_ZIP_PATH"
  ZIP_PATH="$SIGNED_ZIP_PATH"
else
  echo "Skipping notarization. Set CODESIGN_IDENTITY and NOTARY_PROFILE to produce a notarized artifact."
fi

echo "Verifying signature state"
codesign --verify --deep --strict --verbose=2 "$STAGING_DIR/$PRODUCT_NAME.app" || true
spctl --assess --type execute --verbose "$STAGING_DIR/$PRODUCT_NAME.app" || true

echo "Release artifact ready: $ZIP_PATH"
