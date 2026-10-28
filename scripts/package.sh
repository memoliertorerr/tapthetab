#!/usr/bin/env bash
# Packages dist/TapTheTab.app (from scripts/build-app.sh) for distribution:
#
#   dist/TapTheTab-<version>.zip   ditto archive of the app
#   dist/TapTheTab-<version>.dmg   compressed disk image with an /Applications link
#   dist/SHA256SUMS.txt            checksums of the zip and the dmg
#
#   scripts/package.sh [--sign-dmg "<identity>"]
#   scripts/package.sh --checksums-only
#
#   --sign-dmg <identity>  also codesign the dmg (needed before notarizing it)
#   --checksums-only       only rewrite SHA256SUMS.txt (after stapling)
#
# Environment:
#   CODESIGN_KEYCHAIN  optional keychain to take the signing identity from (CI)
set -euo pipefail

APP_NAME="TapTheTab"
VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }
usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; }

DMG_IDENTITY=""
CHECKSUMS_ONLY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign-dmg)
            [[ $# -ge 2 && -n "$2" ]] || die "--sign-dmg needs an identity"
            DMG_IDENTITY="$2"; shift 2 ;;
        --checksums-only) CHECKSUMS_ONLY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument: $1" ;;
    esac
done

[[ "$(uname -s)" == "Darwin" ]] || die "packaging needs macOS (ditto, hdiutil)"

VERSION="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION" =~ $VERSION_PATTERN ]] || die "VERSION '$VERSION' is not MAJOR.MINOR.PATCH[-prerelease]"

DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
ZIP_NAME="$APP_NAME-$VERSION.zip"
DMG_NAME="$APP_NAME-$VERSION.dmg"
ZIP="$DIST/$ZIP_NAME"
DMG="$DIST/$DMG_NAME"

write_checksums() {
    log "Writing SHA256SUMS.txt"
    (
        cd "$DIST"
        shasum -a 256 "$ZIP_NAME" "$DMG_NAME" > SHA256SUMS.txt
        cat SHA256SUMS.txt
    )
}

if [[ $CHECKSUMS_ONLY == 1 ]]; then
    [[ -f "$ZIP" && -f "$DMG" ]] || die "$ZIP_NAME and $DMG_NAME must exist in dist/"
    write_checksums
    exit 0
fi

[[ -d "$APP" ]] || die "$APP not found; run scripts/build-app.sh first"
codesign --verify --deep --strict "$APP" || die "$APP is not validly signed; rebuild it"

rm -f "$ZIP" "$DMG" "$DIST/SHA256SUMS.txt"

# --- zip -----------------------------------------------------------------------
log "Creating $ZIP_NAME"
ditto -c -k --keepParent "$APP" "$ZIP"

# --- dmg -----------------------------------------------------------------------
log "Creating $DMG_NAME"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/tapthetab-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

# hdiutil occasionally fails with "Resource busy" on CI machines; retry a few times.
attempt=1
until hdiutil create \
        -volname "$APP_NAME $VERSION" \
        -srcfolder "$STAGE" \
        -fs HFS+ \
        -format UDZO \
        -imagekey zlib-level=9 \
        -ov \
        "$DMG"; do
    if (( attempt >= 4 )); then
        die "hdiutil create failed after $attempt attempts"
    fi
    echo "hdiutil create failed (attempt $attempt); retrying in $((attempt * 5))s" >&2
    sleep $((attempt * 5))
    attempt=$((attempt + 1))
done

if [[ -n "$DMG_IDENTITY" ]]; then
    log "Signing $DMG_NAME"
    SIGN_ARGS=(--force --sign "$DMG_IDENTITY" --timestamp)
    if [[ -n "${CODESIGN_KEYCHAIN:-}" ]]; then
        SIGN_ARGS+=(--keychain "$CODESIGN_KEYCHAIN")
    fi
    codesign "${SIGN_ARGS[@]}" "$DMG"
    codesign --verify --strict --verbose=2 "$DMG"
fi

hdiutil verify "$DMG" >/dev/null

write_checksums
log "Packaged:"
ls -lh "$ZIP" "$DMG" "$DIST/SHA256SUMS.txt"
