#!/usr/bin/env bash
# Assembles the website (GitHub Pages) into a folder: the page and its stylesheet from
# site/, and the pictures from docs/images/. Everything is self-contained: no scripts,
# fonts or other files are fetched from anywhere.
#
#   scripts/build-site.sh [output folder]     (default: dist/site)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-$root/dist/site}"

rm -rf "$out"
mkdir -p "$out/images"
cp "$root"/site/* "$out/"
cp "$root"/docs/images/*.png "$out/images/"

# Every local file the page refers to must exist.
missing=0
while IFS= read -r ref; do
  if [[ ! -f "$out/$ref" ]]; then
    echo "error: index.html refers to $ref, which was not found" >&2
    missing=1
  fi
done < <(grep -Eoh '(src|srcset|href)="(images/[^"]+|[a-z][a-z0-9.-]*\.(css|svg|png))"' "$out/index.html" \
  | sed -E 's/^[a-z]+="//; s/"$//' | sort -u | { grep -v '^images/demo\.png$' || true; })
if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

# The animation is rendered by CI (the screenshots artifact) and committed afterwards;
# until then the page shows the picture's description instead.
if [[ ! -f "$root/docs/images/demo.png" ]]; then
  echo "warning: docs/images/demo.png is missing; the demo animation will not show." >&2
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "::warning title=Demo animation missing::Commit docs/images/demo.png (from the screenshots artifact of a CI run)."
  fi
fi

echo "Site assembled in $out"
