#!/bin/bash
#
#  release.sh
#  AdSilencer
#
#  Builds, signs, notarizes and staples a DMG for install on another Mac.
#  Run with:  Tools/release.sh
#
#  Needs a Developer ID Application certificate and a stored notary profile:
#      xcrun notarytool store-credentials
#

set -euo pipefail

PROFILE="AdSilencerNotary"
BUILD="$(cd "$(dirname "$0")/.." && pwd)/build"
APP="$BUILD/Release/AdSilencer.app"
DMG="$BUILD/AdSilencer.dmg"

cd "$(dirname "$0")/.."
rm -rf "$BUILD"

echo "Building..."
xcodebuild -scheme AdSilencer -configuration Release \
    -derivedDataPath "$BUILD/dd" CONFIGURATION_BUILD_DIR="$BUILD/Release" \
    build >/dev/null

echo "Verifying the signature..."
codesign --verify --strict --deep "$APP"
# The hardened runtime and the Apple events entitlement are what notarizing
# checks for, and what lets the app keep controlling Spotify.
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "apple-events" \
    || { echo "Apple events entitlement is missing"; exit 1; }

# notarytool exits 0 even when Apple rejects the archive, so read the status
# and print the reasons rather than stapling a ticket that does not exist.
notarize() {
    local out
    out=$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait 2>&1)
    echo "$out"
    if ! grep -q "status: Accepted" <<<"$out"; then
        echo
        echo "Rejected. Reasons:"
        xcrun notarytool log "$(grep -m1 "id:" <<<"$out" | awk '{print $2}')" \
            --keychain-profile "$PROFILE"
        exit 1
    fi
}

# The app is notarized and stapled on its own first. Stapling only the disk
# image leaves the copy dragged out of it without a ticket, so it needs a
# network check to open.
echo "Notarizing the app, which uploads it to Apple..."
ditto -c -k --keepParent "$APP" "$BUILD/AdSilencer.zip"
notarize "$BUILD/AdSilencer.zip"
xcrun stapler staple "$APP"

echo "Packing the disk image..."
mkdir -p "$BUILD/dmg"
cp -R "$APP" "$BUILD/dmg/"
ln -s /Applications "$BUILD/dmg/Applications"
hdiutil create -volname AdSilencer -srcfolder "$BUILD/dmg" \
    -ov -format UDZO "$DMG" >/dev/null

echo "Notarizing the disk image..."
notarize "$DMG"
xcrun stapler staple "$DMG"

# Gatekeeper's own answer, rather than trusting the steps above.
echo "Checking what Gatekeeper says..."
xcrun stapler validate "$APP"
spctl -a -vvv "$APP"

echo
echo "Done: $DMG"
