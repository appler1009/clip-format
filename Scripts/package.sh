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
#   PROVISIONING_PROFILE_APP      base64 of the Developer ID profile for
#                                 com.appler1009.ClipFormat
#   PROVISIONING_PROFILE_PREVIEW  base64 of the Developer ID profile for
#                                 com.appler1009.ClipFormat.Preview
#
# App Groups mean a Developer ID *certificate* is not enough — both binaries
# need a Developer ID provisioning profile or xcodebuild refuses to sign.
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
install_profile() {
  local encoded=$1
  local label=$2
  local dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  mkdir -p "$dir"
  local tmp
  tmp=$(mktemp)
  printf '%s' "$encoded" | base64 --decode > "$tmp"
  local uuid
  uuid=$(security cms -D -i "$tmp" | plutil -extract UUID raw -)
  if [[ -z "$uuid" ]]; then
    echo "error: $label is not a readable provisioning profile" >&2
    exit 1
  fi
  mv "$tmp" "$dir/$uuid.provisionprofile"
  echo "$uuid"
}

signing_args=(CODE_SIGNING_ALLOWED=NO)
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  if [[ -z "${PROVISIONING_PROFILE_APP:-}" || -z "${PROVISIONING_PROFILE_PREVIEW:-}" ]]; then
    echo "error: App Groups require Developer ID provisioning profiles." >&2
    echo "       set PROVISIONING_PROFILE_APP and PROVISIONING_PROFILE_PREVIEW" >&2
    echo "       (base64 of the .provisionprofile for the app and the appex)." >&2
    exit 1
  fi
  echo "==> Installing provisioning profiles"
  app_profile=$(install_profile "$PROVISIONING_PROFILE_APP" "PROVISIONING_PROFILE_APP")
  preview_profile=$(install_profile "$PROVISIONING_PROFILE_PREVIEW" "PROVISIONING_PROFILE_PREVIEW")
  signing_args=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
    DEVELOPMENT_TEAM="${TEAM_ID:-}"
    OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime"
    APP_PROVISIONING_PROFILE="$app_profile"
    PREVIEW_PROVISIONING_PROFILE="$preview_profile"
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

STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "ClipFormat" -srcfolder "$STAGING" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGING"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG"
fi

(cd "$DIST" && shasum -a 256 ./*.zip ./*.dmg > SHA256SUMS.txt)

echo "==> Done"
ls -lh "$DIST"
