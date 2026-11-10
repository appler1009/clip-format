#!/usr/bin/env bash
# Deletes the oldest <NAME>-<version>.dmg files from the update bucket, keeping the newest KEEP (default 5).
#
# Run by publish-update.sh after the new DMG and appcast.xml are uploaded. It only looks at
# <PREFIX>/<NAME>-<major>.<minor>.<patch>.dmg: the appcast, other apps' files (the bucket is shared)
# and anything else are left alone. The appcast points at the newest DMG, so updating is unaffected;
# what goes is old direct links and the way back past the fifth.
#
# Any failure here is a warning, never a failed release (the token may not be allowed to delete).
#
# Environment:
#   PREFIX   the app's folder in the bucket
#   NAME     the DMG's name before the version (letters, digits, - and _)
#   R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET
#   KEEP     how many of the newest to keep [5]
#   PROTECT  a key never to delete: the DMG the appcast points at, which is the oldest one if an old
#            tag is released again
#
# `prune-update-dmgs.sh --select` reads keys on stdin and prints the ones that would be deleted
# (to check the choice by hand).
set -uo pipefail

KEEP="${KEEP:-5}"
PREFIX="${PREFIX:-}"
NAME="${NAME:-}"

warn() { echo "::warning::prune-update-dmgs: $*"; }
valid() { case "$1" in '' | *[!A-Za-z0-9_-]*) return 1 ;; *) return 0 ;; esac; }
valid "$PREFIX" && valid "$NAME" || { warn "PREFIX and NAME must be set, and only letters, digits, - and _; not pruning"; exit 0; }

# Keys on stdin, those to delete on stdout: this app's DMGs by version, all but the newest KEEP, and never PROTECT.
select_old() {
  grep -E "^$PREFIX/$NAME-[0-9]+\.[0-9]+\.[0-9]+\.dmg$" | sort -V \
    | awk -v keep="$KEEP" '{ k[NR] = $0 } END { for (i = 1; i <= NR - keep; i++) print k[i] }' \
    | grep -vxF -- "${PROTECT:-/}"
}

if [ "${1:-}" = "--select" ]; then
  select_old
  exit 0
fi

case "$KEEP" in '' | *[!0-9]*) warn "KEEP is not a number ($KEEP); not pruning"; exit 0 ;; esac
[ "$KEEP" -ge 1 ] || { warn "KEEP must be at least 1; not pruning"; exit 0; }
for v in R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET; do
  [ -n "${!v:-}" ] || { warn "$v is not set; not pruning"; exit 0; }
done
ENDPOINT="https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com/$R2_BUCKET"

s3() { curl --fail --silent --show-error --aws-sigv4 "aws:amz:auto:s3" --user "$R2_ACCESS_KEY_ID:$R2_SECRET_ACCESS_KEY" "$@"; }

LISTING="$(s3 "$ENDPOINT?list-type=2&prefix=$PREFIX%2F$NAME-")" || { warn "could not list the bucket; not pruning"; exit 0; }
# A partial list sorts wrongly, so a truncated one is not acted on.
case "$LISTING" in *"<IsTruncated>true</IsTruncated>"*) warn "more than one page of files; not pruning"; exit 0 ;; esac

OLD="$(printf '%s' "$LISTING" | grep -o '<Key>[^<]*</Key>' | sed -e 's/^<Key>//' -e 's/<\/Key>$//' | select_old)"
if [ -z "$OLD" ]; then
  echo "==> Nothing to prune (keeping the newest $KEEP)"
  exit 0
fi

while IFS= read -r key; do
  if s3 -X DELETE "$ENDPOINT/$key" >/dev/null; then
    echo "==> Deleted $key"
  else
    warn "could not delete $key"
  fi
done <<< "$OLD"
exit 0
