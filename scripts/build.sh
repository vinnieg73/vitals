#!/bin/bash
# Builds Vitals.app. With --install, replaces /Applications/Vitals.app and opens it.
# Build output lives in ~/Library/Caches so Spotlight doesn't index a second copy of the app.
set -euo pipefail
cd "$(dirname "$0")/.."

SCRATCH="$HOME/Library/Caches/VitalsBuild"
swift build -c release --scratch-path "$SCRATCH"
BIN="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)"
APP="$SCRATCH/Vitals.app"

# App icon (all drawn by icon/make-icon.swift). The .icns is the light icon for older macOS; on macOS 26+
# Assets.car (compiled from icon/Vitals.icon) gives the light and Dark mode ("Graphite") versions.
# The dark and layer PNGs aren't committed: drawn here when missing or when the script changed.
[[ icon/make-icon.swift -nt icon/Vitals.icon/Assets/gauge-dark.png ]] && swift icon/make-icon.swift
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
# Build number = commit count, so About tells builds apart ("Version 0.1.0 (123)").
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
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

# The pages (written by the cloud thread). Until they exist, a placeholder stands in for each.
[[ -d Resources ]] && cp -R Resources/. "$APP/Contents/Resources/web/"
for page in window popover help; do
  if [[ ! -f "$APP/Contents/Resources/web/$page.html" ]]; then
    cp Support/placeholder.html "$APP/Contents/Resources/web/$page.html"
    echo "note: Resources/$page.html missing, using the placeholder page"
  fi
done

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Vitals || true
  for _ in $(seq 30); do pgrep -x Vitals >/dev/null || break; sleep 0.1; done
  rm -rf "/Applications/Vitals.app"
  cp -R "$APP" /Applications/
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$LSREGISTER" -f "/Applications/Vitals.app" || true
  open -g "/Applications/Vitals.app"   # -g: launch in the background, never take focus from Vinnie
  echo "Installed to /Applications/Vitals.app"
fi
