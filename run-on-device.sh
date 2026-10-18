#!/bin/bash
# Build the app and push it to a physical iPhone (equivalent to Xcode's Run button).
# Defaults to a Release (production-quality, optimized) build, since this installs
# straight onto a phone used for real matches, not just for debugging.
#
# Usage:
#   ./run-on-device.sh                  # Release build, default device (PHONE_UDID below)
#   ./run-on-device.sh --debug          # Debug build, default device
#   ./run-on-device.sh iphone           # Release build, deploys to "iPhone" (iPhone 15 Pro Max)
#   ./run-on-device.sh --debug iphone   # Debug build, deploys to "iPhone"
#   ./run-on-device.sh <udid>           # Release build, deploys to a specific devicectl identifier

set -euo pipefail
cd "$(dirname "$0")"

PROJECT="FootballStats.xcodeproj"
SCHEME="FootballStats"
CONFIGURATION="Release"

PHONE_UDID="00000000-0000-0000-0000-000000000000"   # your phone's devicectl identifier
IPHONE_UDID="00000000-0000-0000-0000-000000000000"  # optional second device

ARGS=()
for arg in "$@"; do
  case "$arg" in
    --release|-r) CONFIGURATION="Release" ;;
    --debug|-d)   CONFIGURATION="Debug" ;;
    *)            ARGS+=("$arg") ;;
  esac
done

TARGET="${ARGS[0]:-phone}"
case "$TARGET" in
  phone|"") DEVICE_ID="$PHONE_UDID" ;;
  iphone)   DEVICE_ID="$IPHONE_UDID" ;;
  *)        DEVICE_ID="$TARGET" ;;
esac

echo "==> Building $SCHEME ($CONFIGURATION) for device $DEVICE_ID"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "id=$DEVICE_ID" \
  -allowProvisioningUpdates \
  build

BUILD_DIR=$(xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "id=$DEVICE_ID" \
  -showBuildSettings \
  2>/dev/null | awk -F ' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')

APP_NAME=$(xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "id=$DEVICE_ID" \
  -showBuildSettings \
  2>/dev/null | awk -F ' = ' '/ FULL_PRODUCT_NAME /{print $2; exit}')

APP_PATH="$BUILD_DIR/$APP_NAME"
BUNDLE_ID=$(defaults read "$APP_PATH/Info.plist" CFBundleIdentifier)

echo "==> Installing $APP_PATH"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "==> Launching $BUNDLE_ID"
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"

echo "==> Done"
