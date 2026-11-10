#!/bin/bash
# Builds Vitals.app. With --install, replaces /Applications/Vitals.app and opens it.
# Build output lives in ~/Library/Caches so Spotlight doesn't index a second copy of the app.
set -euo pipefail
cd "$(dirname "$0")/.."

SCRATCH="${VITALS_SCRATCH:-$HOME/Library/Caches/VitalsBuild}"   # override to build beside another build
swift build -c release --scratch-path "$SCRATCH"
BIN="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)"
APP="$SCRATCH/Vitals.app"

# App icon (all drawn by icon/make-icon.swift). The .icns is the light icon for older macOS; on macOS 26+
# Assets.car (compiled from icon/Vitals.icon) gives the light and Dark mode ("Graphite") versions.
# The dark and layer PNGs aren't committed: drawn here when missing (after editing the script: --force).
[[ -f icon/icon-1024-dark.png && -f icon/Vitals.icon/Assets/gauge-dark.png ]] || swift icon/make-icon.swift
ICONSET="$SCRATCH/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s icon/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) icon/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$SCRATCH/AppIcon.icns"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"
cp "$BIN/Vitals" "$APP/Contents/MacOS/"
cp Support/Info.plist "$APP/Contents/"
# The version lives in Support/Info.plist and nowhere else: two numbers ("1.0"), and the build number is
# major x 100 + minor (1.0 = 100, 1.1 = 101). Refuse to build a pair that doesn't fit.
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Support/Info.plist)"
if [[ ! "$VERSION" =~ ^([0-9]+)\.([0-9]+)$ ]] || (( BASH_REMATCH[1] * 100 + BASH_REMATCH[2] != BUILD )); then
  echo "error: version $VERSION and build $BUILD don't fit (build = major x 100 + minor)" >&2; exit 1
fi
cp "$SCRATCH/AppIcon.icns" "$APP/Contents/Resources/"
# Needs Xcode 26+ (actool reads Icon Composer files); without it the app keeps the light .icns only.
ACTOOL_OUT="$SCRATCH/actool"
rm -rf "$ACTOOL_OUT"; mkdir -p "$ACTOOL_OUT"
if xcrun --find actool >/dev/null 2>&1 && xcrun actool icon/Vitals.icon --compile "$ACTOOL_OUT" \
     --app-icon Vitals --platform macosx --target-device mac --minimum-deployment-target 14.0 \
     --output-partial-info-plist "$ACTOOL_OUT/partial.plist" >"$ACTOOL_OUT/log.txt" 2>&1 \
   && [[ -f "$ACTOOL_OUT/Assets.car" ]]; then
  cp "$ACTOOL_OUT/Assets.car" "$APP/Contents/Resources/"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string Vitals" "$APP/Contents/Info.plist"
else
  echo "note: no Dark mode icon (actool couldn't compile icon/Vitals.icon; see $ACTOOL_OUT/log.txt)"
fi

# The pages. sample.js is only the fake feed a browser gets (the app never loads it), so it stays out of the app.
for page in window popover help; do
  [[ -f "Resources/$page.html" ]] || { echo "error: Resources/$page.html is missing" >&2; exit 1; }
done
cp -R Resources/. "$APP/Contents/Resources/web/"
rm -f "$APP/Contents/Resources/web/sample.js"

codesign --force --sign - "$APP"
echo "Built $APP (version $VERSION)"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Vitals || true
  for _ in $(seq 30); do pgrep -x Vitals >/dev/null || break; sleep 0.1; done
  rm -rf "/Applications/Vitals.app"
  cp -R "$APP" /Applications/
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$LSREGISTER" -f "/Applications/Vitals.app" || true
  # -g: launch in the background, never take focus from Vinnie. `open` can fail with error -600 when it runs before
  # macOS has finished noting that the old copy quit (2026-11-10: the new build was in place, nothing was running),
  # so try up to 5 times, 2 s apart.
  opened=0
  for try in 1 2 3 4 5; do
    if open -g "/Applications/Vitals.app"; then opened=1; break; fi
    echo "open failed (try $try of 5)" >&2
    [[ $try == 5 ]] || sleep 2
  done
  if [[ $opened != 1 ]]; then
    echo "error: the new build is in /Applications/Vitals.app but could not be started. Start it with: open -g /Applications/Vitals.app" >&2
    exit 1
  fi
  # ...and it must really be running: exactly one Vitals from /Applications (a test copy elsewhere doesn't count)
  N=0
  for _ in $(seq 50); do
    N="$(pgrep -f '^/Applications/Vitals.app/Contents/MacOS/Vitals' | wc -l | tr -d ' ' || true)"
    [[ "$N" != 0 ]] && break
    sleep 0.1
  done
  if [[ "$N" != 1 ]]; then
    echo "error: expected exactly one Vitals running from /Applications, found $N:" >&2
    pgrep -fl 'Vitals.app/Contents/MacOS/Vitals' >&2 || true
    exit 1
  fi
  echo "Installed to /Applications/Vitals.app (one copy running)"
fi
