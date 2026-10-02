#!/bin/bash
# Builds every app icon size and the website images from one 1024x1024 master.
#
#   scripts/build-app-icon.sh                # draw the placeholder icon, then build
#   scripts/build-app-icon.sh --from-master  # use distribution/icon-1024.png as is
#
# To switch to real artwork, replace distribution/icon-1024.png with a
# 1024x1024 PNG and run the script with --from-master. Commit the results.
#
# Outputs:
#   distribution/icon-1024.png                          master icon
#   Plainfile/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png and Contents.json
#   docs/favicon.png (64), docs/apple-touch-icon.png (180)
#   docs/og-image.png (1200x630, placeholder mode only)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MASTER="$REPO_ROOT/distribution/icon-1024.png"
ICONSET="$REPO_ROOT/Plainfile/Resources/Assets.xcassets/AppIcon.appiconset"
DOCS="$REPO_ROOT/docs"

mkdir -p "$REPO_ROOT/distribution" "$ICONSET" "$DOCS"

if [[ "${1:-}" != "--from-master" ]]; then
  WORK_DIR="$(mktemp -d)"
  trap 'rm -rf "$WORK_DIR"' EXIT
  swift "$REPO_ROOT/scripts/app-icon.swift" "$WORK_DIR"
  cp "$WORK_DIR/icon-1024.png" "$MASTER"
  cp "$WORK_DIR/og-image.png" "$DOCS/og-image.png"
fi

test -f "$MASTER" || { echo "missing $MASTER" >&2; exit 1; }

resize() { # size output
  sips -z "$1" "$1" "$MASTER" --out "$2" >/dev/null
}

entries=()
for size in 16 32 128 256 512; do
  resize "$size" "$ICONSET/icon_${size}x${size}.png"
  resize "$((size * 2))" "$ICONSET/icon_${size}x${size}@2x.png"
  entries+=("    { \"filename\" : \"icon_${size}x${size}.png\", \"idiom\" : \"mac\", \"scale\" : \"1x\", \"size\" : \"${size}x${size}\" }")
  entries+=("    { \"filename\" : \"icon_${size}x${size}@2x.png\", \"idiom\" : \"mac\", \"scale\" : \"2x\", \"size\" : \"${size}x${size}\" }")
done

{
  echo '{'
  echo '  "images" : ['
  for i in "${!entries[@]}"; do
    if (( i < ${#entries[@]} - 1 )); then echo "${entries[$i]},"; else echo "${entries[$i]}"; fi
  done
  echo '  ],'
  echo '  "info" : { "author" : "xcode", "version" : 1 }'
  echo '}'
} > "$ICONSET/Contents.json"

resize 64 "$DOCS/favicon.png"
resize 180 "$DOCS/apple-touch-icon.png"

echo "wrote icon sizes to $ICONSET and website icons to $DOCS"
