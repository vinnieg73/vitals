# Vitals

A menu bar app that shows what Activity Monitor shows, with every stat up front instead of behind tabs.

- **Menu bar**: icon only, always the same width (58 pt). Three dials, CPU, GPU and RAM, each needle at how busy
  that part is (RAM = memory used %). A strained dial and its name turn amber, red when critical (RAM: memory
  pressure/swap; CPU or GPU: 85%+ for 30 s). That verdict is made once (`StatusIcon.Judge`, in the sampler) and sent
  to the pages as `strain`, so the icon, the drop-down and the window always agree. Heat or low disk space take over from the dials with a thermometer or
  drive, itself amber or red (no dot or badge). Battery is left to the system's own icon. Preview: `Resources/menubar-states-{light,dark}.png`
  (the pictures Help shows; redraw with `Vitals --render menubar <out.png> [light|dark]`).
- **Click it** to open a popover with the short version (Memory reads % used, RAM used / total and swap used / total, in GB of 1024³ like Activity Monitor;
  GPU reads % busy, the GPU's memory in use and its core count; the full window adds Pixels and Shapes, how busy
  its drawing and geometry halves are;
  Energy reads the whole Mac's power draw in watts ("W for Mac": what runs the Mac itself), from the battery's own meter, then fan speed (rpm,
  or "off"; left out on Macs with no readable fan), then while plugged in what the charger is putting in
  ("To battery 54 W"; "Battery full" or "Not charging" at 0). The big number is what the Mac itself uses, so the
  charger's output is the two added together; the window's Energy readout shows "To battery" too, in place of "Time left" while plugged in. No battery % there: macOS's own icon shows it. Disk and
  Network say "read" / "write" and "in" / "out". In "Memory by app" (and the window's list) a loose process says in
  gray who started it ("Claude Code · folder", or an app), and `node` / `python3` are named after their script. Each Claude Code session's dot is its own model (from that session's own transcript; gray when not known). Macs without a battery show the
  energy impact score there instead: no unit, 100 ≈ one CPU core fully busy, the same score as the app list's Energy column). **⌃⌥⌘V** (or Open Vitals, ⌘O) opens the full window. Its charts switch between the last 5 minutes, the last hour and
  the last 12 hours (a point a minute, gaps where the Mac slept). The installed app keeps that history across restarts in
  `~/Library/Application Support/Vitals/history.json` (written at most every 5 minutes, on quit and before sleep); the
  time Vitals wasn't running shows as a gap. Test builds and every command-line mode keep it in memory only.
- **Right-click or ⌃-click** it for Open at Login (Vitals turns it on by itself the first time the installed copy in /Applications runs, unless you unticked it; if macOS wants your OK, it opens Login Items in System Settings),
  Help and Quit. If another app already holds ⌃⌥⌘V, that menu says so.
- **Help** (⌘?) explains every number in plain English.
- It keeps reading every 2 s while the Mac is awake, lid shut or screen locked too, so the charts have no gap when you
  come back. Only another user's session in front slows it to once a minute.

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
Vitals.app/Contents/MacOS/Vitals --selftest                                     # baseline, busy-clock, model-dot and sampler rules (~25 s)
Vitals.app/Contents/MacOS/Vitals --render window renders/window-dark.png dark   # page to PNG, off screen
Vitals.app/Contents/MacOS/Vitals --render window out.png light --warm 40        # ...after 40 s of live samples
Vitals.app/Contents/MacOS/Vitals --soak 6 window                                # live page off screen, memory every 30 s
```

`--dump --bench` also prints what one sample costs. An option Vitals doesn't know (a typo, or one from a newer build)
prints the known ones and exits, so it can't start a second copy in the menu bar.

The pages can also be checked without the app, in headless Chromium with fake snapshots (needs Node and Playwright):

```bash
node scripts/test-pages.js     # charts and readouts after a gap, hover labels, nothing cut off, no page errors
```

The window's stats and table columns have fixed widths, so every number has to fit the widest it can get. The page
tests feed the window huge values (loads over 100, 100+ GB of swap, TB totals, 999.9 MB/s) at the minimum width
(1100), just past the narrow layout (1181) and wide (1680), light and dark, and fail if any stat or table number is
cut off, a label and its value touch, or the big number's caption ends less than 16 px before the next column. A
new stat or a new number format needs its widest case added to `heavy()` there.

## Layout

- `Sources/Vitals/` — the Swift app: the sampler (System, Devices, Fan, Processes, Sampler, LongHistory for the
  12-hour charts), the menu bar item, the popover and windows (AppDelegate, StatusIcon, Web, Hotkey), and
  Dump/Render/MenuBarPreview/Soak/SelfTest.
- `Resources/` — the pages (window, popover, help, app.css, app.js; sample.js is the fake feed a browser gets) and the
  two menu bar pictures Help shows. The Swift side feeds the pages the snapshot described in `DATA.md`.
- `Support/Info.plist` — the app's Info.plist, and the one place the version lives. Two numbers ("1.0"); the build
  number is major × 100 + minor (1.0 = 100, next 1.1 = 101, 2.0 = 200), and build.sh refuses a pair that doesn't fit.
  About reads it from the bundle ("Version 1.0"). Each release is tagged `v1.0`.
- `HANDOFF.md` — where things stand now. `docs/HISTORY.md` — the dated log of every change before 2026-11-10.
- `icon/make-icon.swift` — draws `icon/icon-1024.png` (light), `icon/icon-1024-dark.png` (Dark mode, "Graphite") and the
  gauge layers in `icon/Vitals.icon/Assets/`. `build.sh` compiles `icon/Vitals.icon` (Icon Composer format) with actool,
  so on macOS 26+ Finder and the Dock show the Graphite icon in Dark mode. `scripts/icon-preview.sh [out-folder]` renders
  both looks with Icon Composer's `ictool` (no window). After editing the script: `swift icon/make-icon.swift --force`.
