#!/usr/bin/env bash
# Signs dist/ClipFormat-<version>.dmg for Sparkle, writes dist/appcast.xml, and uploads both to R2
# under the clipformat/ prefix (the bucket is shared with other apps).
#
# Afterwards it prunes the oldest DMGs there (prune-update-dmgs.sh).
#
# Run by the release workflow after package.sh. With DRY_RUN=1 it signs and writes the appcast
# but uploads nothing.
#
# Environment:
#   SPARKLE_ED_PRIVATE_KEY  the Sparkle EdDSA private key (the text `generate_keys -x` writes)
#   UPDATE_BASE_URL         the public address of the bucket, no trailing slash
#   R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET   (not needed for DRY_RUN)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
die() { echo "error: $*" >&2; exit 1; }

VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml | head -1)"
DMG="dist/ClipFormat-$VERSION.dmg"
APPCAST="dist/appcast.xml"
APP_PLIST="build/DerivedData/Build/Products/Release/ClipFormat.app/Contents/Info.plist"
PREFIX="clipformat"
SIGN="build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"

[ -f "$DMG" ] || die "$DMG not found (run Scripts/package.sh first)"
[ -x "$SIGN" ] || die "$SIGN not found (Scripts/package.sh builds it)"
: "${SPARKLE_ED_PRIVATE_KEY:?SPARKLE_ED_PRIVATE_KEY is not set}"
: "${UPDATE_BASE_URL:?UPDATE_BASE_URL is not set}"
BASE="${UPDATE_BASE_URL%/}/$PREFIX"

# The same build number package.sh stamps into the app, so Sparkle compares like with like.
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PLIST")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_PLIST")"

KEYFILE="$(mktemp)"
trap 'rm -f "$KEYFILE"' EXIT
chmod 600 "$KEYFILE"
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" > "$KEYFILE"

# Prints: sparkle:edSignature="…" length="…"
SIGNATURE="$("$SIGN" --ed-key-file "$KEYFILE" "$DMG")"
case "$SIGNATURE" in *edSignature=*length=*) ;; *) die "unexpected sign_update output" ;; esac

cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>ClipFormat</title>
    <item>
      <title>ClipFormat $VERSION</title>
      <pubDate>$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <enclosure url="$BASE/ClipFormat-$VERSION.dmg" type="application/octet-stream" $SIGNATURE/>
    </item>
  </channel>
</rss>
XML
echo "==> Wrote $APPCAST for $VERSION ($BUILD)"

if [ -n "${DRY_RUN:-}" ]; then
  echo "==> Dry run: not uploading"
  exit 0
fi

: "${R2_ACCOUNT_ID:?}" "${R2_ACCESS_KEY_ID:?}" "${R2_SECRET_ACCESS_KEY:?}" "${R2_BUCKET:?}"
ENDPOINT="https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com/$R2_BUCKET"

upload() { # file key content-type cache-control
  curl --fail --silent --show-error --aws-sigv4 "aws:amz:auto:s3" \
    --user "$R2_ACCESS_KEY_ID:$R2_SECRET_ACCESS_KEY" \
    -H "Content-Type: $3" -H "Cache-Control: $4" \
    --upload-file "$1" "$ENDPOINT/$PREFIX/$2"
  echo "==> Uploaded $PREFIX/$2"
}

# The DMG first, so the feed never points at a file that isn't there yet.
upload "$DMG" "ClipFormat-$VERSION.dmg" application/octet-stream "public, max-age=31536000, immutable"
upload "$APPCAST" appcast.xml application/xml "no-cache"

# Keep the newest few DMGs in the bucket; a failure here is a warning, not a failed release.
PREFIX="$PREFIX" NAME="ClipFormat" PROTECT="$PREFIX/ClipFormat-$VERSION.dmg" Scripts/prune-update-dmgs.sh || echo "::warning::could not prune old DMGs"
