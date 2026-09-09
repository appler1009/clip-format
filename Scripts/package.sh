#!/usr/bin/env bash
#
# Builds, signs, notarizes and packages ClipFormat for distribution.
#
# Signing and notarization are optional: without the environment below the
# script still produces an unsigned .app, .zip and .dmg, which is enough for
# local testing but will trip Gatekeeper on anyone else's Mac.
#
#   SIGNING_IDENTITY              e.g. "Developer ID Application: Your Name (TEAMID)"
#   TEAM_ID                       Apple Developer team identifier
#   NOTARY_APPLE_ID               Apple ID used for notarization
#   NOTARY_PASSWORD               app-specific password for that Apple ID
#
# No provisioning profiles. Outside the App Store an App Group is authorised by
# the team ID prefix on the group identifier, not by a profile, so a Developer
# ID certificate signs both binaries on its own. Profiles would only come back
# if the app adopts a com.apple.developer.* capability (iCloud, push) or ships
# through the Mac App Store.
#
# Usage: Scripts/package.sh [version] [build-number]

set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml | head -1)
VERSION="${1:-$PROJECT_VERSION}"
BUILD_NUMBER="${2:-1}"
DIST="dist"
DERIVED="build/DerivedData"
APP="$DERIVED/Build/Products/Release/ClipFormat.app"

if [[ "$VERSION" != "$PROJECT_VERSION" ]]; then
  echo "error: requested version $VERSION but project.yml says $PROJECT_VERSION" >&2
  echo "       bump MARKETING_VERSION in project.yml and commit before tagging." >&2
  exit 1
fi

echo "==> Generating project"
xcodegen generate

echo "==> Building ClipFormat $VERSION ($BUILD_NUMBER)"
signing_args=(CODE_SIGNING_ALLOWED=NO)
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  signing_args=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
    DEVELOPMENT_TEAM="${TEAM_ID:-}"
    OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime"
    # Left alone, Xcode adds get-task-allow, and the notary service rejects
    # any binary carrying it. Checked again after the build.
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
  )
fi

rm -rf "$DERIVED" "$DIST"
xcodebuild \
  -project ClipFormat.xcodeproj \
  -scheme ClipFormat \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${signing_args[@]}" \
  build

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  echo "==> Checking entitlements"
  # A debug entitlement that survives into a release build costs a notarisation
  # round trip to discover, so fail here instead.
  for binary in "$APP" "$APP/Contents/PlugIns/ClipFormatPreview.appex"; do
    if codesign -d --entitlements :- "$binary" 2>/dev/null | tr -d '\0' | grep -q "get-task-allow"; then
      echo "error: $(basename "$binary") carries com.apple.security.get-task-allow;" >&2
      echo "       the notary service rejects it." >&2
      exit 1
    fi
  done
fi

mkdir -p "$DIST"
ZIP="$DIST/ClipFormat-$VERSION.zip"
DMG="$DIST/ClipFormat-$VERSION.dmg"

if [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_PASSWORD:-}" && -n "${TEAM_ID:-}" ]]; then
  echo "==> Notarizing"
  # notarytool takes an archive, not a bundle; the ticket is stapled to the
  # .app afterwards so both the zip and the dmg carry it.
  ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"
  xcrun notarytool submit "$DIST/notarize.zip" \
    --apple-id "$NOTARY_APPLE_ID" \
    --password "$NOTARY_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait
  xcrun stapler staple "$APP"
  rm -f "$DIST/notarize.zip"
else
  echo "==> Skipping notarization (credentials not set)"
fi

echo "==> Packaging"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Rendering DMG background"
swift Scripts/make-dmg-background.swift Packaging/dmg-background.png

# Window and icon positions are in points and must match
# Scripts/make-dmg-background.swift (640×400 content, icons at 160 and 480).
# Width is exactly the art width so Finder never shows its default white strip
# at the sides; height adds ~28pt for the title bar.
DMG_VOL="ClipFormat"
DMG_CONTENT_W=640
DMG_CONTENT_H=400
DMG_TITLE_H=28
DMG_WIN="{400, 100, $((400 + DMG_CONTENT_W)), $((100 + DMG_CONTENT_H + DMG_TITLE_H))}"
# Finder's icon position is from the top of the window; the background
# script draws from the bottom, so 400 - 188 = 212.
DMG_APP_POS="{160, 212}"
DMG_APPS_POS="{480, 212}"

STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
mkdir "$STAGING/.background"
cp Packaging/dmg-background.png "$STAGING/.background/background.png"

RW="$DIST/rw.dmg"
rm -f "$RW" "$DMG"
hdiutil create -volname "$DMG_VOL" -srcfolder "$STAGING" -ov -format UDRW -fs HFS+ -size 150m -quiet "$RW"
rm -rf "$STAGING"

MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | sed -n 's/.*\(\/Volumes\/.*\)/\1/p' | head -1)
echo "==> Styling $MOUNT"
# Finder reads the background from a file on the volume; the folder stays
# hidden so the user only sees the app and Applications.
osascript <<EOF
tell application "Finder"
  tell disk "$DMG_VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to $DMG_WIN
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set background color of theViewOptions to {65535, 65535, 65535}
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "ClipFormat.app" to $DMG_APP_POS
    set position of item "Applications" to $DMG_APPS_POS
    update without registering applications
    delay 2
    close
    open
    delay 1
    close
  end tell
end tell
EOF
sync
hdiutil detach "$MOUNT" -quiet
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -quiet -o "$DMG"
rm -f "$RW"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG"
fi

(cd "$DIST" && shasum -a 256 ./*.zip ./*.dmg > SHA256SUMS.txt)

echo "==> Done"
ls -lh "$DIST"
