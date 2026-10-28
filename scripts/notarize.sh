#!/usr/bin/env bash
# Notarizes and staples a Developer ID–signed build. Optional: only used when
# signing credentials exist (see .github/workflows/release.yml).
#
#   scripts/notarize.sh --sign "<Developer ID Application identity>"
#
# Expects dist/TapTheTab.app signed with that identity (scripts/build-app.sh --sign ...)
# and dist/TapTheTab-<version>.zip (scripts/package.sh). Then:
#   1. submits the zip to Apple's notary service and waits for the verdict,
#   2. staples the ticket to the .app and re-packages (zip + signed dmg),
#   3. notarizes and staples the dmg,
#   4. rewrites dist/SHA256SUMS.txt.
#
# Environment (App Store Connect API key; values are never printed):
#   NOTARY_KEY_ID      key ID
#   NOTARY_ISSUER_ID   issuer ID
#   NOTARY_KEY_PATH    path to the AuthKey_<id>.p8 private key file
#   CODESIGN_KEYCHAIN  optional keychain holding the signing identity
set -euo pipefail

APP_NAME="TapTheTab"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }
usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; }

IDENTITY=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign)
            [[ $# -ge 2 && -n "$2" ]] || die "--sign needs an identity"
            IDENTITY="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument: $1" ;;
    esac
done

[[ -n "$IDENTITY" && "$IDENTITY" != "-" ]] || die "--sign <Developer ID identity> is required; ad-hoc builds cannot be notarized"
[[ "$(uname -s)" == "Darwin" ]] || die "notarization needs macOS"
for var in NOTARY_KEY_ID NOTARY_ISSUER_ID NOTARY_KEY_PATH; do
    [[ -n "${!var:-}" ]] || die "$var is not set"
done
[[ -f "$NOTARY_KEY_PATH" ]] || die "NOTARY_KEY_PATH does not point to a file"

VERSION="$(tr -d '[:space:]' < VERSION)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/$APP_NAME-$VERSION.zip"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

[[ -d "$APP" ]] || die "$APP not found; run scripts/build-app.sh --sign ... first"
[[ -f "$ZIP" ]] || die "$ZIP not found; run scripts/package.sh first"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/tapthetab-notary.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# submit <file>: uploads, waits, and fails (printing Apple's log) unless Accepted.
submit() {
    local file="$1" result="$WORK/submit.json" status id
    log "Submitting $(basename "$file") for notarization (this can take a few minutes)"
    xcrun notarytool submit "$file" \
        --key "$NOTARY_KEY_PATH" \
        --key-id "$NOTARY_KEY_ID" \
        --issuer "$NOTARY_ISSUER_ID" \
        --wait \
        --output-format json > "$result" || true

    status="$(plutil -extract status raw -o - "$result" 2>/dev/null || echo unknown)"
    id="$(plutil -extract id raw -o - "$result" 2>/dev/null || echo "")"
    echo "notarization status: $status${id:+ (submission $id)}"

    if [[ "$status" != "Accepted" ]]; then
        if [[ -n "$id" ]]; then
            xcrun notarytool log "$id" \
                --key "$NOTARY_KEY_PATH" \
                --key-id "$NOTARY_KEY_ID" \
                --issuer "$NOTARY_ISSUER_ID" || true
        else
            cat "$result" >&2 || true
        fi
        die "notarization of $(basename "$file") failed"
    fi
}

# 1. Notarize the app (via its zip) and staple the ticket to the bundle.
submit "$ZIP"
log "Stapling $APP_NAME.app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# 2. Re-package so the zip and the dmg contain the stapled app; sign the dmg.
scripts/package.sh --sign-dmg "$IDENTITY"

# 3. Notarize and staple the dmg itself.
submit "$DMG"
log "Stapling $(basename "$DMG")"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# 4. Stapling changed the dmg, so refresh the checksums.
scripts/package.sh --checksums-only

log "Gatekeeper assessment"
spctl --assess --type execute --verbose=2 "$APP" || die "Gatekeeper rejected the notarized app"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" || die "Gatekeeper rejected the notarized dmg"

log "Notarized and stapled: $APP, $ZIP, $DMG"
