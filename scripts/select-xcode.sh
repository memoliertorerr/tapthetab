#!/usr/bin/env bash
# CI helper: selects the newest stable Xcode of a major version installed under
# /Applications (GitHub's macOS images ship several, e.g. Xcode_26.2.app,
# Xcode_26.3.app, plus betas, which are skipped).
#
#   scripts/select-xcode.sh [major]      # default major: 26
#
# Runs `sudo xcode-select -s`, so it is meant for CI machines, not your Mac.
set -euo pipefail

MAJOR="${1:-26}"
[[ "$MAJOR" =~ ^[0-9]+$ ]] || { echo "error: major version must be a number" >&2; exit 1; }

best=""
best_version=""
for candidate in /Applications/Xcode_"$MAJOR"*.app; do
    [[ -d "$candidate/Contents/Developer" ]] || continue
    name="$(basename "$candidate" .app)"     # Xcode_26.3 / Xcode_26.3.0 / Xcode_26.3_beta
    version="${name#Xcode_}"
    # Stable releases only: digits and dots, and exactly this major version.
    [[ "$version" =~ ^${MAJOR}(\.[0-9]+){0,2}$ ]] || continue
    if [[ -z "$best_version" ]] || [[ "$(printf '%s\n%s\n' "$best_version" "$version" \
        | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)" == "$version" ]]; then
        best="$candidate"
        best_version="$version"
    fi
done

if [[ -z "$best" ]]; then
    echo "::error::No stable Xcode $MAJOR found in /Applications. Installed:" >&2
    ls -d /Applications/Xcode*.app >&2 || true
    exit 1
fi

echo "Selecting $best"
sudo xcode-select -s "$best/Contents/Developer"
xcodebuild -version
swift --version
