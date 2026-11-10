# Vitals: Mac build brief (history: the original brief from 2026-10-17)

> **Out of date, kept only as a record.** Much has changed since: the pages are edited in this repo like the Swift
> code (there is no separate cloud thread), the menu bar icon is three dials, the hotkey is ⌃⌥⌘V, Open at Login turns
> itself on, and the treemap is gone. For how things are now read README.md, HANDOFF.md and DATA.md.

Vinnie asked for a Mac tool that shows what Activity Monitor shows, with every stat up front instead of behind
tabs. He picked the "Plain English" mockup with the Memory Map's RAM picture inside it
(design/06-plain-english.html and design/04-treemap.html are the approved mockups; screenshots in design/).

## Who owns what
- The cloud thread writes the pages: Resources/window.html, popover.html, help.html, app.css, app.js, sample.js.
  Do not edit them; if a page needs a change, say exactly what in HANDOFF.md / your report.
- This Mac session writes everything else: Package.swift, Sources/Vitals/*.swift, scripts/build.sh, icon, README,
  HANDOFF.md.
- DATA.md is the contract between them. Follow it exactly; if a field truly can't be read, send null and note it.

## The app
- SwiftPM executable "Vitals" (no Xcode project), AppKit, macOS 14+, LSUIElement (menu bar app, no Dock icon while
  only the menu is used; show in Dock while the main window is open is fine). Bundle id com.vinnie.vitals.
  Build like swarm-watch: scripts/build.sh builds into ~/Library/Caches/VitalsBuild (keep build output out of
  Spotlight-indexed folders), makes Vitals.app, ad-hoc codesign; `--install` replaces /Applications/Vitals.app.
- Sampler: one background timer every 2 s builds the snapshot in DATA.md (Mach host_statistics64,
  host_processor_info, sysctl vm.swapusage / kern.memorystatus_level / kern.memorystatus_vm_pressure_level,
  getloadavg, proc_listallpids + proc_pid_rusage(RUSAGE_INFO_V4) + proc_pidinfo, IOKit for battery
  (AppleSmartBattery, IOPSCopyPowerSourcesInfo), GPU (IOAccelerator PerformanceStatistics), disk
  (IOBlockStorageDriver Statistics), getifaddrs for network. Per-process network: `nettop -P -L 1 -x -J bytes_in,bytes_out`
  on its own slower cadence is acceptable. Keep Vitals itself light: target < 2% CPU, < 120 MB.
- Main window: titled "Vitals", ~1280x880, min 1100x760, remembers its frame. One WKWebView loading
  Resources/window.html via loadFileURL (allowingReadAccessTo the Resources folder). Follows system light/dark.
- Menu bar item (native, NSStatusItem): a small gauge glyph (template image, needle at memory pressure).
  States from the snapshot:
  - normal: gauge only, template (gray).
  - warn (level warn, or swap > 75% full): gauge + "RAM 78%" + a small amber dot (#E09A1D).
  - critical: red rounded background (#D0342C) with white "Out of RAM".
  Click opens an NSPopover (~356 wide) with a WKWebView of Resources/popover.html that sizes to its content
  (page posts no size; measure document.body.scrollHeight after load and on update, or fix 560 tall).
- Help window: WKWebView of Resources/help.html. Reached from the popover, from the app menu (Help → Vitals Help ⌘?),
  and from the page's links.
- App menu: About, Open Vitals ⌘O, Vitals Help ⌘?, Open at Login (checkmark, SMAppService, off by default), Quit ⌘Q.
  Global hotkey ⌥⌘V toggles the main window (Carbon RegisterEventHotKey, no accessibility permission needed).
- quitProcess: terminate politely (NSRunningApplication.terminate or SIGTERM); never SIGKILL; refuse pids owned by root.

## Testing (off screen, always)
Vinnie was annoyed today by a test window left on his screen. Never open windows on his screen to test.
- `Vitals --dump` prints one snapshot JSON (after two samples, so rates are real) and exits. Check every DATA.md
  field against Activity Monitor numbers via command-line equivalents (vm_stat, sysctl, memory_pressure, top -l 1).
- `Vitals --render <page> <out.png> [light|dark]` loads a page in an offscreen WKWebView (window off screen or
  never ordered front), feeds it the live snapshot, waits ~1.5 s, takeSnapshot to PNG, exits. Render window, popover
  and help in both themes into ~/Code/Utilities/vitals/renders/ (gitignored) so the cloud thread can look at them.

## Rules
- Private GitHub repo vinnieg73/vitals; never put ~/.claude settings or credentials in it.
- Keep HANDOFF.md in this folder up to date (status, done, next, gotchas) at each milestone.
- Creating the repo, pushing, and installing to /Applications need Vinnie's own typed words in the thread.
