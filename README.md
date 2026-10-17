# Vitals

A menu bar app that shows what Activity Monitor shows, with every stat up front instead of behind tabs.

- **Menu bar**: a small gauge whose needle is at memory pressure. When memory gets tight it says
  "RAM 78%" with an amber dot. When it's critical it turns red and says "Out of RAM".
- **Click it** to open a popover with the short version. **⌃⌥⌘V** (or Open Vitals, ⌘O) opens the full window.
- **Help** (⌘?) explains every number in plain English.

## Build

```bash
scripts/build.sh            # builds ~/Library/Caches/VitalsBuild/Vitals.app
scripts/build.sh --install  # replaces /Applications/Vitals.app and opens it
```

Needs macOS 14+ and the Xcode command line tools. The build lives in ~/Library/Caches so Spotlight
doesn't index a second copy of the app.

## Test without opening anything

```bash
Vitals.app/Contents/MacOS/Vitals --dump [--scan]                                # one snapshot as JSON
Vitals.app/Contents/MacOS/Vitals --render window renders/window-dark.png dark   # page to PNG, off screen
```

`--scan` waits for the first "biggest space users" scan. `--dump --bench` also prints what one
sample costs.

## Layout

- `Sources/Vitals/` — the Swift app: the sampler (System, Devices, Fan, Processes, DiskScan, Sampler),
  the menu bar item, the popover and windows (AppDelegate, StatusIcon, Web, Hotkey), and Dump/Render.
- `Resources/` — the pages (window, popover, help, app.css, app.js, sample.js). The Swift side feeds
  them the snapshot described in `DATA.md`.
- `Support/` — Info.plist and the placeholder page used when a page is missing.
- `icon/make-icon.swift` — draws `icon/icon-1024.png`.
