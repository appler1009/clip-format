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

# The window layout (size, icon positions, background) lives in
# Packaging/dmgbuild-settings.py and must match Scripts/make-dmg-background.swift.
# dmgbuild writes the Finder layout itself instead of scripting Finder, so it
# works on a headless runner where Finder does not answer AppleScript.
DMG_VOL="ClipFormat"
DMGBUILD_VERSION="1.6.5"
if command -v dmgbuild >/dev/null; then
  DMGBUILD=dmgbuild
else
  VENV="build/dmgbuild-venv"
  if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
    echo "==> Installing dmgbuild $DMGBUILD_VERSION"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet "dmgbuild==$DMGBUILD_VERSION"
  fi
  DMGBUILD="$VENV/bin/dmgbuild"
fi

echo "==> Building DMG"
rm -f "$DMG"
"$DMGBUILD" -s Packaging/dmgbuild-settings.py \
  -D app="$APP" -D background=Packaging/dmg-background.png \
  "$DMG_VOL" "$DMG"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG"
fi

(cd "$DIST" && shasum -a 256 ./*.zip ./*.dmg > SHA256SUMS.txt)

echo "==> Done"
ls -lh "$DIST"
