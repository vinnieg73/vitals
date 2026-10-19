# Vitals — handoff

_Last updated 2026-10-19 ~01:15 UTC by the Mac session._

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

## Memory leak fix (2026-10-18)
- With the main window open, the page's web process sat at 400–450 MB (20–30% CPU) and the app grew ~6 MB/min
  (96 → 114 MB in 3 min, in "owned unmapped"). Causes: every 2 s Swift inlined ~300 KB of JSON into a new script
  (WebKit compiled each one), and the page rebuilt ~700 table rows.
- Fixes: page renders only the rows in view (b028519, cloud thread); Swift pushes through one fixed
  `callAsyncJavaScript` script with the JSON as an argument, and skips windows that are hidden or covered.
- `--soak 6 window` after the fix (off screen, 182 updates): app 18 → 24 MB, then flat at 23.5 MB. Page 72 → 100 MB,
  still creeping ~1 MB/min at the end (97 MB at 3.5 min, 100.6 MB at 6 min). Off-screen pages may skip painting, so
  recheck in the real window: `ps`/`footprint` on the window's WebContent after an hour open.

## Strip charts redesign (2026-10-18)
- Vinnie picked mockup "02 Strip Charts". Pages landed in 4ff2a11 and are installed. Shots in docs/shots/
  (strip-window.png, strip-popover.png, plus -dark), rendered with `--render … --warm 40`; no page JS errors.
- Swift side done: snapshot `live` (DATA.md) = the last 150 samples at 2 s of pressurePct, swapUsedBytes,
  cpuUserPct, cpuSystemPct, gpuPct, diskReadBps, diskWriteBps, netInBps, netOutBps, energyImpact; `energy.impact`
  = sum of top-level Proc.energy. GPU was already read every 2 s (only the 1-hour history is 30 s).
- energyImpact / energy.impact are null while no page is showing (process rows aren't sampled then, to keep idle
  CPU low) and on the first sample. So the energy strip has a gap for the time the window was closed.
- Per Proc: `compressedBytes` (task_name_for_pid + TASK_VM_INFO, own processes only) and `idleWakeupsPs`.
  Claude's sandbox VM reports more compressed than its footprint (6.4 GB vs 3.7 GB): guest memory, raw kernel number.
- Cost (`--dump --bench`): 24.9 ms per tick with process rows (1.25% of a core), 10.6 ms without (0.53%), same as
  before the change.
- Noticed, not fixed: `user` is null for the ~260 processes owned by root and other users (PROC_PIDTBSDINFO fails
  for them); PROC_PIDT_SHORTBSDINFO would give their uid.
- Measured on the installed app (2026-10-18): idle with the window closed 2.0–2.6% CPU, 22 MB (a bit above the 2%
  target; this morning it was 1.7–1.9%). Window open (`--soak 10 window`, off screen): app 3.0–3.7% CPU and flat at
  23 MB; page 1.5–2.3% CPU (likely low, off screen pages may skip painting), memory 62 MB at 30 s, 93 MB at 4 min
  (live buffers filling), then 96–99 MB through 10 min.

## RAM bar shading (2026-10-18)
- b5daf0d (cloud thread): the memory bar shades what's really in use (App, Wired, Compressed) strong and Cached
  faint, no new colors. Installed; light and dark renders checked (in dark mode "strong" is the light shade).

## Apple Music privacy prompt (2026-10-18)
- Trigger (from tccd's log): Vitals asked for kTCCServiceMediaLibrary ~3 s after launch at 17:31, 17:32 and 17:51,
  i.e. right as the launch disk scan started. The scan walked all of ~/Library/Caches, which holds Apple Music's
  caches (com.apple.Music, com.apple.AMPLibraryAgent, com.apple.iTunes…).
- Fix: App caches skips com.apple.* (except com.apple.dt.* = Xcode), Apple caches named without the prefix, and
  media-named folders. Biggest space users is unchanged in practice (Xcode simulators 35 GB, Code 30 GB…).
- Checked: two launches after the fix, both scans ran, no Vitals entries at all in tccd's log.

## Fixed-width menu bar item (2026-10-19)
- Why: Vinnie said the icons kept sliding in and out from behind the notch. Vitals switched between the bare gauge
  (18 pt) and gauge + " RAM 78% ●" or the "Out of RAM" pill (90–107 pt), and swap hovering at the 75% line flipped it often.
- First fix (e3cdebf): always gauge + "RAM NN%" at a fixed 107 pt. Vinnie then picked **icon only** (via the coordinator).
- Now: gauge + a dot slot, never any text. Normal: template gauge, clear dot. Warn: amber dot. Critical: red gauge +
  red dot (the "Out of RAM" pill is gone). `statusItem.length` is set once at launch from the real button
  (`StatusIcon.fixedLength`) = **34 pt**, and never changed.
- Updates only touch the button when the state changes (pressure is an Int now). Warn from swap has hysteresis:
  enters over 75%, leaves under 72%.
- Checked: `--status-log --status-test` (cycles 8 test states every 2 s, including critical) for 3 min: 98 updates,
  every one length 34.0 / button frame 34.0.
- help.html's "Menu bar icon" section was updated to match by the cloud thread (d9a314d) and installed 2026-10-19
  ~00:54Z; the installed app logged length 34.0 / button 34.0 at launch.
- Then Vinnie couldn't see Vitals at all: Claude Meter's 234 pt slot left no room and macOS's own overflow (« at
  the notch, MenuBarAgent) took Vitals, the leftmost item since it was relaunched last. Claude Meter went to 193 pt
  (v0.9.21) and both apps set `statusItem.autosaveName` ("Vitals" here), so a ⌘-drag sticks across relaunches.
  No position seeding: on macOS 27 "NSStatusItem Preferred Position" values aren't screen coordinates (probed: 50–150
  → x 1266, 200 → 1146, 250–270 → 1108, 290+ → 899 with Claude Meter at 354). Vinnie's defaults hold Vitals = 260
  (set while probing), which puts it right of Claude Meter: logged at window x 1108, 50 wide (34 + padding), Claude
  Meter at 899, 50.5 pt free beside the notch (right edge 848.5 on the 1512 pt built-in display).
- `--status-log` prints length, button width, fitting width and the button window's screen x/width on each change; `--status-test` fakes the states.
  Run them with `open -n <app> --stdout <file> --args --status-log --status-test`, quit the installed copy first,
  and kill the test copy after (it shows in the real menu bar).

## Menu bar icon shows what's strained (2026-10-19)
- Asked for by Vinnie (via the coordinator): the icon shows the area under pressure. `StatusIcon.Judge` (sampler queue)
  rates each area every tick; the most severe wins, ties go Memory, Heat, Disk, CPU.
  - Memory (`memorychip`): as app.js memState. Critical: level critical, or swap ≥ 97% with pressure ≥ 85. Strained:
    level warn, pressure ≥ 70 or swap ≥ 75%. Leaves strained under 65 / 72%; critical's swap line drops to 95% / 80.
  - Heat (`thermometer.medium`): thermal serious = strained, critical = critical.
  - No battery state: removed the same day at Vinnie's ask, since macOS's own battery icon already shows the charge.
    The window and popover keep their battery numbers.
  - Disk (`internaldrive`): free < 10% strained, < 3% critical; leaves at 12% / 4%.
  - CPU (`cpu`): ≥ 85% for 30 s straight (a dip under 75%, or under 85% before it's flagged, restarts the clock);
    leaves under 75%. Never critical.
- Calm is the gauge as before. Symbols are drawn into an 18×16 canvas (the gauge's width) at 14 pt medium, template when
  strained (follows light/dark), red palette when critical; the dot slot is always there. Fixed 34 pt in every state.
- Different from the spec: memory critical follows memState (adds the swap ≥ 97% + pressure ≥ 85 case) rather than
  only macOS's level; the calm gauge still needs a valid pressure.
- Checked: a scratch harness fed fake snapshots: every threshold, the hysteresis, the 30 s CPU rule (and its reset)
  and the tie order behaved as above. `--status-log --status-test` cycled all 12 states (before battery came out) in the real menu bar for
  2.3 min: 70 updates, all length 34.0 / button 34.0 (window 50). After install Vitals sits at window x 1100, right of
  Claude Meter. At install the real state was memory strained (swap 94%, level warn).
- Previews: `Vitals --render menubar <out.png> [light|dark]` (`MenuBarPreview.swift`, real status bar buttons off
  screen; its offscreen buttons measure 44 pt, the real one 34). Committed as `docs/shots/menubar-states-{light,dark}.png`.
- After battery came out: the harness again (battery at 5% unplugged now stays calm; heat beats disk on a tie), 8 states,
  `--status-test` 24 updates all 34.0 at window x 1100. Previews re-rendered and copied over
  `Resources/menubar-states-{light,dark}.png` (the coordinator asked; Help shows them).
- Help's menu bar section is the cloud thread's to update.

## Memory used % for the pages (2026-10-19)
- Vinnie found the memory number read differently from the others (pressure, not how full) and picked "used %" for the
  big number. Swift adds `live.memUsedPct` (memory.usedBytes / totalBytes × 100, one decimal, same 150 × 2 s ring as
  the rest); DATA.md's live block has it. The pages are the cloud thread's. The menu bar icon still goes by pressure/swap.
- Checked: `--dump` gave memUsedPct [78.8, 78.9] with 2 points, matching usedBytes / totalBytes = 78.9%.
- The cloud's pages (0937197) show it: Memory's big number and chart are used %, pressure moved into the list.
  Installed 2026-10-19 ~03:35Z; `--render --warm 40` of window and popover, light and dark, show "80% Used · 14.38 GB"
  with a flat ~80% line and no page errors; committed over `docs/shots/strip-*.png`. Vitals still at window x 1100.

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
  or swap > 75%) adds an amber dot. Critical is a red gauge + red dot. Fixed 34 pt (see "Fixed-width menu bar item").
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
- `--dump [--scan] [--bench]`, `--render <page> <out.png> [light|dark] [--scan] [--warm <s>]` (--warm samples live
  every 2 s first so the strip charts have history), `--soak <minutes> [page]`
  (leak check: live page off screen, prints app and page memory every 30 s).
- Pages get updates through one fixed `callAsyncJavaScript` script with the JSON as an argument (Web.swift `push`).
  Windows that are closed, minimized, covered or on another Space get no updates; when one comes back into view
  it gets the latest snapshot at once (`windowDidChangeOcclusionState`).
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
- Privacy prompts: walking all of ~/Library/Caches made macOS ask "Allow Vitals to access … Apple Music?"
  (kTCCServiceMediaLibrary, plus a silent Full Disk Access check) ~0.3 s into every launch scan. Fixed 2026-10-18:
  App caches now sums only non-Apple cache folders (`DiskScan.skipCache`). Testing the scan as a child of the
  Claude session checks Claude's grants, not Vitals', so check the installed app with
  `/usr/bin/log show --last 10m --predicate 'process == "tccd"' | grep -i vitals` after a launch.
- Ad hoc signing gives every build a new identity, so macOS forgets any privacy answer after a rebuild ("Failed to
  match existing code requirement"). An "Apple Development" identity exists in the keychain, but signing with it
  may pop a keychain password dialog, so build.sh stays ad hoc (like Vinnie's other tools) until he OKs that.
- Root and other users' processes have null memory, so they sort last. kernel_task and WindowServer never
  show in "using the most memory".
- Never test by opening windows or the menu bar item on Vinnie's screen; use `--dump` and `--render`.
- Don't run `memory_pressure -l/-p`. They create real memory pressure.
- `nettop` must have `-n` (see CLAUDE.md lessons).
