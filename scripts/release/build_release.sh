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
ZIP_PATH="$DIST_DIR/$PRODUCT_NAME.zip"

mkdir -p "$DIST_DIR"
rm -rf "$ARCHIVE_PATH" "$STAGING_DIR" "$ZIP_PATH"

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

mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"

ditto -c -k --sequesterRsrc --keepParent "$STAGING_DIR/$PRODUCT_NAME.app" "$ZIP_PATH"

echo "Release artifact ready: $ZIP_PATH"
