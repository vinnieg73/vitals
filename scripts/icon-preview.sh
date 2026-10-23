#!/bin/bash
# Renders the app icon's light and Dark mode looks from icon/Vitals.icon with Icon Composer's command-line tool,
# with no window (safe while Vinnie works). Needs Xcode 26+.  scripts/icon-preview.sh [out-folder]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/vitals-icon-preview}"
mkdir -p "$OUT"
[[ -f icon/Vitals.icon/Assets/gauge-dark.png ]] || swift icon/make-icon.swift
ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
for r in Default Dark; do
  "$ICTOOL" icon/Vitals.icon --export-image --platform macOS --rendition "$r" --width 512 --height 512 --scale 1 \
    --output-file "$OUT/icon-$r.png"
done
echo "Wrote $OUT/icon-Default.png and $OUT/icon-Dark.png"
