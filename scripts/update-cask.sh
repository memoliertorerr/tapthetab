#!/usr/bin/env bash
# Point Casks/tapthetab.rb at a published release.
#   scripts/update-cask.sh <version> <sha256-of-dmg>
# The sha256 is the TapTheTab-<version>.dmg line in the release's SHA256SUMS.txt.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <version> <sha256>" >&2
  exit 64
fi
version="$1"
sha="$2"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: bad version '$version'" >&2; exit 65; }
[[ "$sha" =~ ^[0-9a-f]{64}$ ]] || { echo "error: bad sha256 '$sha'" >&2; exit 65; }

cask="$(cd "$(dirname "$0")/.." && pwd)/Casks/tapthetab.rb"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
sed -E \
  -e "s/^  version \"[^\"]*\"/  version \"$version\"/" \
  -e "s/^  sha256 \"[^\"]*\"/  sha256 \"$sha\"/" \
  "$cask" > "$tmp"
mv "$tmp" "$cask"
echo "updated $cask to $version"
