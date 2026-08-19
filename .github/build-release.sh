#!/bin/bash
# Builds a distributable Twixodus.app and zips it into dist/Twixodus.zip.
#
#   .github/build-release.sh [version]
#
# By default the app is ad-hoc signed. Set CODESIGN_IDENTITY to a
# "Developer ID Application: ..." identity to sign for real distribution
# (hardened runtime + secure timestamp, ready for notarization).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.0.0-dev}"
IDENTITY="${CODESIGN_IDENTITY:--}"
DERIVED=build/ReleaseDerivedData
APP="$DERIVED/Build/Products/Release/Twixodus.app"
ZIP="dist/Twixodus.zip"

xcodegen generate

xcodebuild -project Twixodus.xcodeproj -scheme Twixodus -configuration Release \
    -derivedDataPath "$DERIVED" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" \
    build

if [ "$IDENTITY" != "-" ]; then
    # Real distribution signing: notarization requires the hardened runtime
    # and a secure timestamp. The app has no nested frameworks, so signing
    # the bundle itself is sufficient.
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
fi

mkdir -p dist
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Built $ZIP"
