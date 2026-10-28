#!/usr/bin/env bash
# Builds dist/TapTheTab.app from the SwiftPM package and code-signs it.
#
#   scripts/build-app.sh [--universal] [--sign "<identity>"]
#
#   --universal        build for arm64 and x86_64 (default: this Mac's arch only)
#   --sign <identity>  codesign identity, e.g. "Developer ID Application: Name (TEAMID)".
#                      Default "-" = ad-hoc signature (fine for local use and for
#                      unsigned CI builds; not notarizable).
#
# Environment:
#   CODESIGN_KEYCHAIN  optional keychain to take the signing identity from (CI)
#   SKIP_ICON=1        don't generate AppIcon.icns
#
# macOS only. Works the same locally and on GitHub Actions.
set -euo pipefail

APP_NAME="TapTheTab"
PRODUCT="TapTheTab"
VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

die() { echo "error: $*" >&2; exit 1; }
warn() { echo "warning: $*" >&2; }
log() { echo "==> $*"; }

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; }

UNIVERSAL=0
IDENTITY="-"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --universal) UNIVERSAL=1; shift ;;
        --sign)
            [[ $# -ge 2 && -n "$2" ]] || die "--sign needs an identity (use - for ad-hoc)"
            IDENTITY="$2"; shift 2 ;;
        --sign=*)
            IDENTITY="${1#--sign=}"
            [[ -n "$IDENTITY" ]] || die "--sign needs an identity (use - for ad-hoc)"
            shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument: $1" ;;
    esac
done

[[ "$(uname -s)" == "Darwin" ]] || die "the app bundle can only be built on macOS (the core builds anywhere: swift build --target TapTheTabCore)"
for tool in swift codesign plutil; do
    command -v "$tool" >/dev/null 2>&1 || die "'$tool' not found; install Xcode or the Command Line Tools"
done

# --- Version and build number ------------------------------------------------
[[ -f VERSION ]] || die "VERSION file missing"
VERSION="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION" =~ $VERSION_PATTERN ]] || die "VERSION '$VERSION' is not MAJOR.MINOR.PATCH[-prerelease]"

BUILD="$(git rev-list --count HEAD 2>/dev/null || true)"
[[ "$BUILD" =~ ^[0-9]+$ ]] || BUILD=1

ARCH_LABEL="$(uname -m)"
[[ $UNIVERSAL == 1 ]] && ARCH_LABEL="universal: arm64 + x86_64"
log "Building $APP_NAME $VERSION (build $BUILD, $ARCH_LABEL)"

# --- Compile -----------------------------------------------------------------
SWIFT_ARGS=(-c release)
if [[ $UNIVERSAL == 1 ]]; then
    SWIFT_ARGS+=(--arch arm64 --arch x86_64)
fi

swift build "${SWIFT_ARGS[@]}" --product "$PRODUCT"
BIN_DIR="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)"
BINARY="$BIN_DIR/$PRODUCT"
[[ -f "$BINARY" ]] || { ls -la "$BIN_DIR" >&2 || true; die "built binary not found at $BINARY"; }

if command -v lipo >/dev/null 2>&1; then
    ARCHS="$(lipo -archs "$BINARY")"
    echo "architectures: $ARCHS"
    if [[ $UNIVERSAL == 1 ]]; then
        for arch in arm64 x86_64; do
            [[ " $ARCHS " == *" $arch "* ]] || die "universal build is missing $arch"
        done
    fi
fi

# --- Assemble the bundle -----------------------------------------------------
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"
chmod 755 "$CONTENTS/MacOS/$APP_NAME"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# SwiftPM resource bundles (none today; copied in case a target gains resources).
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
    log "Copying resource bundle $(basename "$bundle")"
    cp -R "$bundle" "$CONTENTS/Resources/"
done
shopt -u nullglob

sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD/g" Resources/Info.plist > "$CONTENTS/Info.plist"
if grep -q '__[A-Z]*__' "$CONTENTS/Info.plist"; then
    die "unsubstituted placeholder left in Info.plist"
fi
plutil -lint "$CONTENTS/Info.plist"

# --- Icon --------------------------------------------------------------------
if [[ "${SKIP_ICON:-0}" == 1 ]]; then
    warn "SKIP_ICON=1: building without an app icon"
else
    ICON_TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapthetab-icon.XXXXXX")"
    trap 'rm -rf "$ICON_TMP"' EXIT
    log "Generating app icon"
    if swift scripts/make-icon.swift "$ICON_TMP/AppIcon.iconset" \
        && iconutil -c icns "$ICON_TMP/AppIcon.iconset" -o "$CONTENTS/Resources/AppIcon.icns"; then
        echo "icon: $CONTENTS/Resources/AppIcon.icns"
    else
        rm -f "$CONTENTS/Resources/AppIcon.icns"
        warn "icon generation failed; continuing without an app icon"
    fi
fi

# --- Sign ----------------------------------------------------------------------
ENTITLEMENTS="$ROOT/Resources/TapTheTab.entitlements"
[[ -f "$ENTITLEMENTS" ]] || die "entitlements file missing: $ENTITLEMENTS"

# Extended attributes (Finder info, quarantine, ...) make codesign fail.
xattr -cr "$APP" 2>/dev/null || true

SIGN_ARGS=(--force --options runtime --entitlements "$ENTITLEMENTS" --sign "$IDENTITY")
if [[ "$IDENTITY" == "-" ]]; then
    log "Signing ad-hoc (not notarizable; Gatekeeper will ask users to confirm the first launch)"
else
    log "Signing with the configured identity"
    SIGN_ARGS+=(--timestamp)
fi
if [[ -n "${CODESIGN_KEYCHAIN:-}" ]]; then
    SIGN_ARGS+=(--keychain "$CODESIGN_KEYCHAIN")
fi
codesign "${SIGN_ARGS[@]}" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | sed 's/^/    /'

if command -v vtool >/dev/null 2>&1; then
    vtool -show-build "$CONTENTS/MacOS/$APP_NAME" 2>/dev/null | grep -E '^ *(platform|minos|sdk) ' | sed 's/^ */    /' || true
fi

log "Built $APP"
