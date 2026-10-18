# Vitals — handoff

_Last updated 2026-10-17 (evening) by the Mac session._

## Status
- The Swift side is built and green (`scripts/build.sh`). `--dump` matches vm_stat, sysctl,
  memory_pressure, top and system_profiler on this Mac. `--render` works off screen.
- The pages in `Resources/` came from the cloud thread (commit 4a88c23). Don't edit them here; send page fixes back.
- Git: PRIVATE repo github.com/vinnieg73/vitals, main. Created and pushed 2026-10-17 on Vinnie's typed OK
  ("create the private vitals repo, push it and install it").
- **Installed** to /Applications/Vitals.app and launched 2026-10-17 (pid 80685 at the time). Process is running and
  its main thread is idle in the event loop. The menu bar icon itself couldn't be checked from here: on this
  macOS, menu bar items don't show up in CGWindowList at all (not even Claude Meter's), so Vinnie has to look.
- Renders of all three pages in light and dark are in `renders/` (gitignored). `--render` now prints page JS errors;
  none showed up.
- Not yet tried by hand: popover sizing, right-click menu, ⌃⌥⌘V, Help window, quitProcess, Open at Login,
  Dock show/hide.

## Measured on the installed app (2026-10-17)
- Idle (menu bar only, after the launch scan): 1.7–1.9% CPU over 2.5 min of `top`, 21 MB footprint (top MEM),
  73 MB RSS. Under both targets (2% CPU, 120 MB). The launch scan itself took ~45 s.
- The disk scan at launch runs ~50 s at 50–80% of one core (~43 s of CPU, QoS .background so E cores and
  throttled I/O). Since 2026-10-17 it runs **once at launch**, then every 30 min **only while the main window is
  open** (right away on open if the last scan is over 30 min old). Before, it repeated every 30 min regardless,
  which averaged ~2.4% CPU on its own.

## Page issues (for the cloud thread)
- Fixed in 3547b54: steady big tile, tile values never clipped, "collecting…" on the sparklines.
- Fixed in 477007f: near-equal apps keep their tile order (unless one changes by >8%); narrow Claude tiles say
  "Code" / "App". Two renders a few seconds apart had the same order. Caveat: each `--render` is a fresh page with
  one update, so the keep-the-order logic itself only runs in the live app, across ticks.

## Stats-only cleanup (2026-10-18)
- Vinnie asked for "just the stats, no extra fluff". The cloud thread did the pages (02afab5): no headline,
  quickest-fix box, verdict lines, tags or gray descriptions. Help window and its menu items stay (every tool
  gets a Help page). Installed and relaunched; renders checked; the popover fits its shorter content.
- Fixed in 8c701f8: RAM map tiles under 40 px wide or 34 px tall fold into "Everything else". Two dark
  renders checked: every tile value is whole.
- Right after launch, Vitals itself tops "Most energy" for ~45 s (the launch disk scan). Expected, but visible.

## Done
- `Package.swift` (SwiftPM, macOS 14, executable "Vitals"), `Support/Info.plist` (LSUIElement,
  com.vinnie.vitals).
- Sampler (every 2 s, background queue) builds the full DATA.md snapshot:
  - memory: app = internal − purgeable, cached = external + purgeable, used = app + wired + compressed,
    free = total − used − cached; pressure = 100 − kern.memorystatus_level; level from
    kern.memorystatus_vm_pressure_level (1/2/4); swap from vm.swapusage; swap-outs × 16 KB pages.
  - cpu: host_processor_info deltas; per-core kinds come from the device tree (on this M3 Pro, logical
    CPUs 0–5 are E and 6–10 are P), and P cores are sent first; getloadavg.
  - gpu: IOAccelerator "Device Utilization %". energy: IOPS + AppleSmartBattery (health =
    NominalChargeCapacity ÷ DesignCapacity, capped at 100); when plugged in, minutesLeft =
    remaining Wh ÷ PowerTelemetryData.SystemLoad; fan from the SMC (F0Ac); thermal from ProcessInfo.
  - disk: Finder-style free space (includes purgeable), read/write rates from internal
    IOBlockStorageDrivers only (disk images skipped); bigUsers from a background scan every 30 min.
  - network: primary interface (SystemConfiguration), 64-bit counters via NET_RT_IFLIST2.
  - "today" totals: a midnight baseline kept in UserDefaults (`dailyBaseline`).
  - history: one point per 30 s (an average of that window's samples), up to 120 points.
  - processes: proc_listallpids + proc_pid_rusage V4 (phys_footprint, CPU ticks → ns via the
    timebase, disk I/O, wakeups) + PROC_PIDTASKINFO threads; per-process network from
    `nettop -P -n -L 1` every 10 s, only while the main window is open.
- Grouping: helpers go under their app (by responsible pid, falling back to the app bundle path), followed up
  to the top app. The Claude desktop app's Virtualization VM appears as "Sandbox virtual machine".
  Every `claude` CLI (any install: ~/.local/share/claude/versions/…, the desktop app's
  claude-code/…/claude.app) becomes a `session` under `group:claude-code`, named by its cwd, with the
  model from the newest transcript in ~/.claude/projects. Claude Code's built-in ugrep/rg children (same
  binary, other argv[0]) are folded into their session; orphaned ones show as "ugrep — left over
  from Claude Code".
- Menu bar item (NSStatusItem): gauge template image with the needle at pressure. Warn state (level warn,
  or swap > 75%) shows gauge + "RAM 78%" + an amber dot. Critical shows a red pill with "Out of RAM".
  Left-click toggles the popover; right-click shows a small menu.
- Popover: 356 wide, sized to the page's content (measured after load and on every update).
- Main window 1280×880 (min 1100×760), frame remembered ("VitalsMain"), follows system light/dark.
  The Dock icon shows only while a window is open. The page is dropped when the window closes.
- Help window (from the menu, ⌘?, the popover, or any link to help.html#section).
- App menu: About, Open Vitals ⌘O, Vitals Help ⌘?, Open at Login (SMAppService), Hide, Quit ⌘Q;
  Edit menu so copy/paste works in the search field. Global hotkey ⌃⌥⌘V (Carbon) toggles the window; the
  right-click menu shows it on Open Vitals. (Was ⌥⌘V, which took Finder's "Move Item Here".)
- quitProcess: refuses pid ≤ 1, Vitals itself, root's and other users' processes; apps get
  NSRunningApplication.terminate(), everything else SIGTERM. SIGKILL is never used.
- `--dump [--scan] [--bench]`, `--render <page> <out.png> [light|dark] [--scan]`.
- Icon: `icon/make-icon.swift` draws a gray gauge whose needle sits in an amber arc.

## Cost (measured with `--dump --bench`)
- 26 ms of CPU per tick with process rows (~1.3% of one core) and 15 ms without (~0.75%).
  Process rows are only sampled while a page is showing.
- Memory: the sampler alone is 31 MB resident. With AppKit + one WKWebView loaded (`--render window`),
  peak RSS was 250 MB. That includes shared WebKit framework pages and the 2x snapshot bitmap, so it
  overstates the app. **Measure the installed app** with
  `ps -o rss=,%cpu= -p $(pgrep -x Vitals)` while idle and with the popover open, against the 120 MB target.

## Fields sent as null (and why)
- Per-process `memBytes`, `cpuPct`, `cpuTimeSec`, `threads`, `energy`, `diskReadBps`/`diskWriteBps`
  are null for **root and other users' processes** (kernel_task, WindowServer, mds_stores, ~190 rows).
  macOS only gives those to privileged tools (`top` is setuid root, Activity Monitor uses a helper).
  So `totals.threads` counts only your own processes' threads (about 2,700, against `top`'s ~3,900).
  - Possible fix later: a small privileged helper (SMAppService daemon). It needs an admin prompt,
    so it's Vinnie's call.
- `disk.bigUsers` is null until the first scan finishes (a few seconds to minutes after launch).
- `disk.readTodayBytes` / `writtenTodayBytes` and `network.*TodayBytes` count **since boot** until
  Vitals has been running across a midnight, as DATA.md allows. Today that's ~10 TB read, because
  the Mac has been up 8 days. After the first midnight they're exact.
- `energy.minutesLeft` is null when plugged in and the draw is under 0.5 W, or when there's no battery.

## Notes for the pages (cloud thread)
- An app with helpers is sent as one summed row: `id: "group:<app name slug>"` (e.g. `group:claude`,
  `group:safari`), `kind: "app"`, and `pid` = the app's main pid, so quitProcess quits the app.
  Its children include the app's own process as `id: "pid:N"` with `note: "the app itself"`.
  An app without helpers is a plain `pid:N` row.
- Swift sets `note` only for: "the app itself", "virtual machine", "left over from Claude Code",
  and the Claude Code group ("8 sessions"). The page's own table covers the rest.
- Swift calls `Vitals.update(json)` and `Vitals.scrollTo(section)` via `typeof Vitals !== 'undefined'`,
  so a page-level `const Vitals` works.
- Biggest space users skips folders macOS guards with a privacy prompt: Desktop, Documents, Downloads,
  Pictures/Photos, Movies, Music, the Trash and app containers. The mockup's "Downloads" and
  "Photos library" rows won't appear. What's scanned: Xcode simulators, Xcode build files, the
  Claude VM bundle, app caches, and every other folder in your home folder (Code, .cache, .npm…).

## Next (the plan agreed with the cloud thread)
1. ~~Commit, create the private repo, push main, tell the cloud thread.~~ Done 2026-10-17.
2. ~~Pull the pages, build, render light/dark.~~ Done 2026-10-17.
3. ~~Install and launch.~~ Done 2026-10-17. Vinnie to confirm the gauge shows in the menu bar.
4. ~~Treemap fixes, disk scan CPU, hotkey to ⌃⌥⌘V.~~ Done 2026-10-17.

## Open decisions
- Privileged helper for root processes' numbers (needs an admin prompt once)?
- Should Biggest space users include Downloads/Documents? It would ask for permission once.

## Gotchas
- The "no privacy prompt" claim for the disk scan was tested only as a child of the Claude session, so macOS
  checked Claude's privacy grants, not Vitals'. The scan starts ~3 s after launch, so if a
  "Vitals would like to access…" prompt ever appears, it'll be right then. The scan only touches
  ~/Library/Developer, ~/Library/Caches, ~/Library/Application Support/Claude/vm_bundles and non-protected
  home folders, so it shouldn't happen.
- Root and other users' processes have null memory, so they sort last. kernel_task and WindowServer never
  show in "using the most memory".
- Never test by opening windows or the menu bar item on Vinnie's screen; use `--dump` and `--render`.
- Don't run `memory_pressure -l/-p`. They create real memory pressure.
- `nettop` must have `-n` (see CLAUDE.md lessons).
