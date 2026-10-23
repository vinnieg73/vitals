# Vitals

A menu bar app that shows what Activity Monitor shows, with every stat up front instead of behind tabs.

- **Menu bar**: icon only, always the same width (58 pt). Three dials, CPU, GPU and RAM, each needle at how busy
  that part is (RAM = memory used %). A strained dial and its name turn amber, red when critical (RAM: memory
  pressure/swap; CPU or GPU: 85%+ for 30 s). Heat or low disk space take over from the dials with a thermometer or
  drive and an amber or red dot. Battery is left to the system's own icon. Preview: `docs/shots/menubar-states-{light,dark}.png`
  (`Vitals --render menubar <out.png> [light|dark]`).
- **Click it** to open a popover with the short version. **⌃⌥⌘V** (or Open Vitals, ⌘O) opens the full window.
- **Right-click or ⌃-click** it for Open at Login (if macOS wants your OK, it opens Login Items in System Settings),
  Help and Quit. If another app already holds ⌃⌥⌘V, that menu says so.
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
Vitals.app/Contents/MacOS/Vitals --dump                                         # one snapshot as JSON
Vitals.app/Contents/MacOS/Vitals --selftest                                     # baseline, busy-clock and sampler rules (~25 s)
Vitals.app/Contents/MacOS/Vitals --render window renders/window-dark.png dark   # page to PNG, off screen
Vitals.app/Contents/MacOS/Vitals --render window out.png light --warm 40        # ...after 40 s of live samples
Vitals.app/Contents/MacOS/Vitals --soak 6 window                                # live page off screen, memory every 30 s
```

`--dump --bench` also prints what one sample costs.

The pages can also be checked without the app, in headless Chromium with fake snapshots (needs Node and Playwright):

```bash
node scripts/test-pages.js     # charts and readouts after a gap, hover labels, no page errors
```

## Layout

- `Sources/Vitals/` — the Swift app: the sampler (System, Devices, Fan, Processes, Sampler),
  the menu bar item, the popover and windows (AppDelegate, StatusIcon, Web, Hotkey), and Dump/Render/Soak/SelfTest.
- `Resources/` — the pages (window, popover, help, app.css, app.js, sample.js). The Swift side feeds
  them the snapshot described in `DATA.md`.
- `Support/` — Info.plist and the placeholder page used when a page is missing.
- `icon/make-icon.swift` — draws `icon/icon-1024.png` (light), `icon/icon-1024-dark.png` (Dark mode, "Graphite") and the
  gauge layers in `icon/Vitals.icon/Assets/`. `build.sh` compiles `icon/Vitals.icon` (Icon Composer format) with actool,
  so on macOS 26+ Finder and the Dock show the Graphite icon in Dark mode. `scripts/icon-preview.sh [out-folder]` renders
  both looks with Icon Composer's `ictool` (no window). After editing the script: `swift icon/make-icon.swift --force`.
