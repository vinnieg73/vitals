# Vitals — history

The dated log of every change up to 2026-11-05, moved here from HANDOFF.md on 2026-11-10 so the handoff can stay short.
Newest first, then the original build notes. Parts of the older sections describe things that were later changed or
removed (the single gauge icon, the folder scan, the 1-hour history, the cloud thread owning the pages): the dates say when
each was true. For how things are now, read HANDOFF.md and README.md.


## 2026-11-05: Vitals always opens at login (Vinnie: "The vitals app needs to always launch on startup"; shipped 461f122; first install read `notFound`, so it needed the follow-up fix; now enabled in Login Items)
- `AppDelegate.keepLoginItemOn()` at the end of launch: registers `SMAppService.mainApp` when its status is
  `.notRegistered` or `.notFound` (a never-registered copy reads `notFound` here) and he hasn't unticked Open at Login from the menu (UserDefaults `loginTurnedOffByUser`, set by
  `toggleLogin`). Only runs from /Applications/Vitals.app, so test builds never register themselves; `--selftest`,
  `--dump` and `--render` never reach it. `requiresApproval` is left alone (no nagging).
- `Vitals --login-status` prints the SMAppService status (read only). Careful: an OLD installed build ignores that flag and
  starts a normal second copy; only run it on a build that has the flag (a test build in the cache shows `notFound`).
- Gotcha: removing Vitals in System Settings → Login Items makes it `.notRegistered` again, so the next launch re-adds
  it; to opt out use the menu's Open at Login (that sets the flag).
- Selftest: 3 new "login:" checks for the rule.

## 2026-11-05: watts to the battery next to what the Mac uses (Vinnie: "show the wattage going to the battery and the wattage being used to run the macbook"; shipped with the login change)
- The big Energy number was already what runs the Mac (SystemLoad). New: `energy.batteryW` = PowerTelemetryData
  BatteryPower (what goes into the battery), sent plugged in only, 0 when full / held at a limit, null on battery.
  Checked on his Mac: 30.2 W Mac + 54.5 W to battery = 84.7 W from the charger (SystemPowerIn); full battery reads 0.
- Popover third line is now "To battery 54 W" ("Battery full" / "Not charging" at 0) instead of "Charging 85 W"; the window's
  Time left slot shows "To battery". `chargerW` stays in the data (DATA.md) but no page shows it any more. Help
  term "To battery" replaces "Charging".
- Vinnie then asked to "see both numbers presented in the drop down": the big number's label is now "W for Mac" (was
  "W draw"; "W to run Mac" fit only 7 px from the chart, "W for Mac" starts at 246 vs plot edge 222), so the two read as a
  pair: "22.5 W for Mac" / "To battery 54 W".
- Not checked: the sign of BatteryPower on battery (it's only used plugged in).

## 2026-11-05: charging watts (Vinnie: "go ahead with that please"; shipped f0a6efe)
- `Power.telemetry()` reads PowerTelemetryData once for both SystemLoad (the Mac's draw, `watts`) and SystemPowerIn
  (what the charger puts in: the Mac's draw plus into the battery). The energy block adds `chargerW`, null unless
  plugged in; read every tick like the watts.
- Popover Energy row: a third line "Charging 85 W" while charging, "Charger 30 W" when plugged in but not charging
  (full or held at a limit). Window Energy readout: while plugged in the "Charging" / "Charger" row takes the Time
  left row (plugged in that was only a what-if estimate), so both columns stay 3 rows. Help term "Charging".
- Checked: live dump on Vinnie's Mac while charging: watts 22.5, chargerW 84.7 (100 W charger). Worst-case width
  "Charging 140 W" starts at 254 px vs the plot's right edge 222; selftest (new charger check), test-pages pass.

## 2026-10-31: more GPU detail (Vinnie: "like the CPU tab and memory tab"; shipped 3c3cdbe)
- `GPU.stats()` (Devices.swift) reads the IOAccelerator's Device / Renderer / Tiler Utilization % and "In use system
  memory" in one pass; the snapshot's `gpu` adds `rendererPct`, `tilerPct`, `memBytes` (DATA.md).
- Popover GPU row: % big, then "Memory X GB" and "N cores" (same shape as the Memory row). Pixels / Shapes (renderer /
  tiler) were tried there but crowd the chart at worst-case widths and nearly always match the big number, so they
  live in the window's GPU readout (Pixels, Shapes, Memory) and Help's GPU term instead.
- Checked: worst-case width "Memory 99.9 GB" starts at 251 px vs the plot's right edge 222; selftest, test-pages pass.

## 2026-10-31: 5 min / 1 hour / 12 hours switch in the full window (shipped 3c3cdbe)
- Vinnie OK'd the mockup; the popover stays at 5 minutes. History in memory only (starts over with Vitals; my default,
  he didn't object).
- `LongHistory.swift`: a point a minute, per-series averages of non-null samples, nil minutes for sleep (capped), clock
  going back starts a new minute, last point = the minute in progress, 720 max. `Sampler` adds every tick (so it fills
  with the window closed and the lid shut) and sends `long` only while the window shows (`setWindowOpen` → `wantLong`),
  also in `withFreshRows`. `--render window` sets it too. Cost while the window shows: ~2 ms to build + encode a full
  12 h block (~69 KB) per tick, measured with a scratch bench; nothing extra otherwise.
- Pages: `Strip.setRange(cap, divs)` (app.js; default CAP 150 / fifths, so the popover is untouched). window.html: the
  `.seg` switch in the header, `RANGES`, `C` = what the charts and hover read (L or `longView(LONG)`), readouts keep
  reading L. A snapshot without `long` keeps the last one. Hover time "−45 min" / "−2 h 05 min" on long ranges; axis
  and gridlines per range (6 gaps: 10 min / 2 h); footer names the range.
- Selftest: 7 "long:" checks. Headless (scratch range.js on sample.js, which now has a 12 h `long` with a sleep gap):
  readouts identical across ranges, axis/grid/footer/hover right, back to 5 min unchanged, no script errors.
- Checked: a 12 h redraw (whole window update) ~3.5 ms headless vs ~2.3 ms at 5 min; header fits at 1000 px (window
  min is 1100). The window coming back while the popover is open now kicks a sample (`updateLive`), so the long
  charts aren't the cached ones shifted.
- Gotcha: a Mac without a battery has a mostly empty 12 h Energy chart (energy impact is only read while a page shows).

## 2026-10-31: keep sampling with the lid shut (Vinnie picked A; shipped 3c3cdbe)
- Vinnie: "when the mac is shut but still awake" the popover's charts should be full when he opens it. `AppDelegate`
  still tracks the rest reasons (screens, locked, session) but `slowsSampling` makes only "session" (another user in
  front) drop to once a minute. Screens asleep or locked: every 2 s as usual, plus a
  `beginActivity(.userInitiatedAllowingIdleSystemSleep)` token so App Nap doesn't stretch the timer (idle system sleep
  still allowed). Cost with no page: ~1.5 ms CPU per tick (0.07% of a core).
- Selftest: two new rest checks. Not checked on the Mac: a real lid-shut stretch (needs Vinnie; `--status-log` shows
  "rest screens on → every 2 s").
- His follow-up: a longer overview (hours) inside the full window only; the popover stays at 5 minutes. Mockup first.

## 2026-10-31: three visual fixes (Vinnie: "implement all of those"; shipped 9b446dd)
- Energy chart full: `Power.watts()` (`Devices.swift`) reads only the battery's `PowerTelemetryData` property (cached
  service, locked), every tick, page or not. `--bench` without rows 1.4 → 1.5 ms. Battery details and fan stay page-only.
  Selftest: "watts every tick even with no page".
- Popover Disk / Network say "read" / "write" and "in" / "out" after the unit (like the window).
- Names: Swift step 3 in `group()` gives top-level loose processes `startedBy` ("Claude Code · <cwd folder>" or the app,
  up the ppid chain, 12 hops) and renames a runtime (`isRuntime`: node, python*, ruby, bun, deno) after its script
  (`scriptName`: a node_modules file → its package, index/main/cli/dist/bin/src/lib → the folder, `-m mod` → mod; flags
  and bare words skipped). Shown gray after the name in the popover's "Memory by app" and the window's list; searchable.
  Selftest has 11 script-name cases. sample.js has a "vite" row started by Claude Code.
- Window Energy subtitle is now "On 96 W charger" (the "On power · 96 W charger" form was cut off).
- Fix found in review: a page opening within 0.5 s of a background tick got the snapshot's battery and fan, read when
  a page last showed (maybe hours ago). `energySection(fresh:impact:)` in `Sampler.swift` is now shared, and
  `withFreshRows` calls it with fresh: true.
- Width checked headless at worst case (999.9 MB/s read, 999 KB/s write, 12,345 rpm, 188.8 W): every popover row's
  text stays right of the plot (Memory is still the widest).
- Gotcha: a session started in ~/Code reads "Claude Code · Code" (the folder's name).

## 2026-10-31: battery % out of the popover (Vinnie: he has it in the menu bar already; shipped on his "ship it")
- `Resources/popover.html` Energy row is now "24.7 W draw" then "Fan 2,495 rpm" / "Fan off". The window still shows
  battery, time left, health and cycles. Popover doc shots re-rendered.

## 2026-10-31: fan speed in the popover (Vinnie: "ship it"; committed, pushed, installed)
- Vinnie asked for fan speed in the popover without making it busier. `Resources/popover.html` Energy row: big
  "24.7 W draw" (the label rides on the number like Memory's "% used"), then "Battery 75%", then "Fan 2,495 rpm" /
  "Fan off". Fan line only when `energy.fanRPM` is a number; battery line only with a battery. No battery and no watts:
  "85.5 score". A first try with "Battery 76% · Fan 2,543 rpm" on one line ran into the strip chart: keep them apart.

## 2026-10-31: Energy card shows watts (Vinnie picked option A; committed ad9b10c, pushed, installed)
- Why: the card read "129.1 / Battery 79%" with no unit. That was `energy.impact`, a unitless score: the sum over
  top-level processes of `cpuPct + 0.02 × wakeups/s` (`Processes.swift` ~L164), 100 ≈ one core busy, and it leaves out
  root / `_windowserver` rows. Help's "over 20 is a lot" was meant for one app, not the total.
- Now: `Power.Reading.watts` (`Devices.swift`) = `PowerTelemetryData.SystemLoad` mW → W, one decimal, on battery or
  plugged in. `energy.watts` and a new live series `powerW` (`Sampler.swift`), read only while a page shows (same as
  impact; null otherwise, so the chart gaps). `withFreshRows` refreshes watts too, so opening the popover isn't "–".
- Pages: `V.useWatts(s, L)` (app.js) is true when the feed has watts. Popover row "8.0 W / Power draw / Battery 73%";
  window big "8.0 W, Power draw, whole Mac", chart scale in W. No battery (desktop Macs) → the old score, labelled
  "Energy score". The app list's Energy column stays the per-app score. Help: new "Power draw" term; "Energy impact"
  now says it's per app, no unit, 100 ≈ one core.
- sample.js has `energy.watts` + `live.powerW`; `?gaps` nulls them too. test-pages.js's gap snapshot nulls watts.
- Checked 2026-10-31 on battery: `--dump` watts 16 vs ioreg SystemLoad 15967 mW; `--selftest` all passed (new check:
  watts present and sane where there's a battery); `node scripts/test-pages.js` all passed; off-screen renders of popover
  and window look right; headless check of the no-battery fallback shows "Energy score", no script errors.
- The window's Energy subtitle now says "On power · 96 W charger", so the charger's rating isn't read as the draw.
  `docs/shots/strip-{window,popover}{,-dark}.png` re-rendered (`--warm 40`) to show the new card.
- Not checked: SystemLoad while plugged in (the old time-left estimate already used it plugged in, so expected fine).

## 2026-10-30: "RAM suddenly halved" checked, not a Vitals bug (no code change)
- Vinnie saw RAM used drop by about half. At 20:00Z `vm_stat` gave anonymous − purgeable 5.7, wired 2.8, compressor
  1.2 = 9.6 GiB, which is what Vitals' formula gives. Vitals had been running since Oct 27 (no restart, no reset).
- Cause, most likely: a throwaway iOS simulator (Pocket Cactus work does `simctl create` throwaways) shut down and was
  deleted around 19:57Z. Sim crash reports (`"platform":7`) ran until 19:56:57; three sim device folders are gone; load
  average fell from ~69 to 17. No jetsam kills, no big app quit, no macOS update; the Claude app last restarted 04:57Z.
- Swap stayed at ~4.2 GB: normal, macOS only pulls it back when needed. Gotcha: `log` is a zsh builtin, use `/usr/bin/log`.

## 2026-10-25: RAM used / total in the popover
- `Resources/popover.html`: the Memory row reads "76% used", then "RAM 13.7 / 18 GB", then the swap line. Used is
  `memory.usedBytes` (app + wired + compressed, Activity Monitor's "Memory Used"; cached files not counted) over
  `totalBytes`, in GiB like the swap line. Gray (`--ink-3`) like the other sub-lines; only swap carries a warn/crit color.
- `Resources/help.html`: a "RAM used" term above Swap, with yours as "13.5 of 18 GB".
- Checked: `--dump` against `vm_stat` (wired 3.07, compressor 6.02, anonymous − purgeable 4.43 GiB: matches), off-screen
  `--render popover` light and dark (three lines fit the 52 px row), `node scripts/test-pages.js` all passed. Installed with
  `scripts/build.sh --install`.

## Status
- The Swift side is built and green (`scripts/build.sh`). `--dump` matches vm_stat, sysctl,
  memory_pressure, top and system_profiler on this Mac. `--render` works off screen.
- The pages in `Resources/` came from the cloud thread (commit 4a88c23); since the repo moved to one tree they're edited here
  like the Swift side (2026-10-25: the RAM line). Check them with `node scripts/test-pages.js` and `--render`.
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
  - Memory (`memorychip`): as app.js memStateAt (cloud 5ed169c). Swap by size, never by % full (macOS adds a 1 GB
    swap file only when the ones it has are nearly full, so % full is nearly always high; Vinnie's 5 GB was five
    files, not a cap). warnAt = max(4 GiB, 45% of RAM) (8.1 GiB here), critAt = 75% of RAM; RAM falls back to 16 GiB
    like the pages. Strained: level warn, pressure ≥ 70, or swap ≥ warnAt; clears under 65 / warnAt − 1 GiB.
    Critical: level critical, or pressure ≥ 85 with swap ≥ critAt; clears under 80 or critAt − 1 GiB.
  - Heat (`thermometer.medium`): thermal serious = strained, critical = critical.
  - No battery state: removed the same day at Vinnie's ask, since macOS's own battery icon already shows the charge.
    The window and popover keep their battery numbers.
  - Disk (`internaldrive`): free < 10% strained, < 3% critical; leaves at 12% / 4%.
  - CPU (`cpu`): ≥ 85% for 30 s straight (a dip under 75%, or under 85% before it's flagged, restarts the clock);
    leaves under 75%. Never critical.
- Calm is the gauge; since 2026-10-19 ~03:42Z its needle is memory used % (usedBytes / totalBytes, the same as
  `live.memUsedPct` and the window's big number), not pressure; Vinnie wanted them to match. Strain logic still goes
  by pressure / swap size / level. Strained states carry no needle value, so they don't redraw as memory moves.
  After install the needle was at 79 (dump: 78.5%). Symbols are drawn into an 18×16 canvas (the gauge's width) at 14 pt medium, template when
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
- Swap rule change (2026-10-19 ~03:40Z): fake-snapshot checks of every line above (his 4.7 of 5 GB at pressure 50 =
  calm; 8 GiB RAM → warn at 4 GiB). Installed; with his real numbers (pressure 50, level normal, swap 4.65 GiB) the
  icon is calm, the plain gauge, 34 pt at window x 1100.
- Help's menu bar section is the cloud thread's to update.

## Memory used % for the pages (2026-10-19)
- Vinnie found the memory number read differently from the others (pressure, not how full) and picked "used %" for the
  big number. Swift adds `live.memUsedPct` (memory.usedBytes / totalBytes × 100, one decimal, same 150 × 2 s ring as
  the rest); DATA.md's live block has it. The pages are the cloud thread's. The menu bar icon still goes by pressure/swap.
- Checked: `--dump` gave memUsedPct [78.8, 78.9] with 2 points, matching usedBytes / totalBytes = 78.9%.
- The cloud's pages (0937197) show it: Memory's big number and chart are used %, pressure moved into the list.
  Installed 2026-10-19 ~03:35Z; `--render --warm 40` of window and popover, light and dark, show "80% Used · 14.38 GB"
  with a flat ~80% line and no page errors; committed over `docs/shots/strip-*.png`. Vitals still at window x 1100.

## Per-part menu bar icon mockups (2026-10-19)
- Vinnie liked #20 "Three lines with numbers" and #23 "Three dials" from the cloud's "Vitals Menu Bar" artifact.
  `docs/mockups/menubar-20-23.png` draws them plus two variants each on real status bar buttons off screen, light and
  dark, calm / memory tight / CPU busy. Measured widths: 20 = 122 pt, 20b filled + letters = 104, 20c lines + one
  number = 74, 23 = 58, 23b numbers under dials = 58, 23c numbers beside = 96 (today's icon 34). Throwaway Swift tool,
  deleted after. Vinnie picked **23, three dials** (below).

## Three-dial menu bar icon (2026-10-19)
- Built to the coordinator's brief (dl-1 in `docs/mockups/menubar-dials.js`). `StatusIcon.dials`: 58×22 pt image, dials
  at x 9 / 29 / 49, y 10.9 from the top, r 6.9, arc 190° → −10°, stroke 1.7, needle to r − 2.1, hub 1.6; 7 pt
  semibold CPU / GPU / RAM at baseline 19.6. Needles: `cpu.totalPct`, `gpu.pct`, memory used % (null → 0).
- `State` is now the three needles (whole %, so under 1% of movement doesn't redraw) + the levels of every strained
  area. Several dials can be colored at once. GPU got CPU's rule (85%+ for 30 s, leaves under 75%, warn only);
  `Area` gained `.gpu`, busy clocks are per area.
- Heat or disk strained → `takeover`: their symbol + amber/red dot (28×16 image, centered), over the dials whatever
  else is strained (heat wins a heat/disk tie).
- All calm: template image (follows the menu bar). Anything colored: not a template, drawn with labelColor /
  secondaryLabelColor for the button's effectiveAppearance, so AppDelegate KVOs `effectiveAppearance` and redraws.
- `StatusIcon.helpStates` (9) is what `--render menubar` shows; `allStates` (12, incl. 0/0/0, 100/100/100 and RAM crit +
  CPU warn) is what `fixedLength` measures and `--status-test` cycles.
- Checked: release build clean; `--render menubar` light/dark by eye (needles 0 → far left, 100 → far right, colors on the
  right dials, labels not clipped); copied to `docs/shots/` and `Resources/menubar-states-{light,dark}.png` (coordinator
  asked). Installed; `--status-log --status-test` for 30 s: every state length 58.0 / button 58.0 (window 74), Vitals
  at window x 1035. Claude Meter logged at x 858, 169 wide ("1% · 2h06m  wk 69%"), right edge 1027, so it has 178.5 pt
  right of the notch edge (848.5). Its two-digit form (177) fits; the "~100%" (209) and longest (250) forms don't, and
  then macOS moves an item into the « overflow. A ⌘-drag only picks which item goes; ~72 pt has to be freed elsewhere.
  Vitals' right edge also moved from 1150 to 1109 (it only grew 24 pt), so something right of it took ~41 pt; can't see
  what (status items aren't in CGWindowList on macOS 27).
- Fake-snapshot harness (scratch, deleted): 19 checks pass. GPU 90 for 28 s ok, 32 s warn, holds at 80, clears at 70;
  CPU and GPU clocks are independent; a dip under 85 before it's flagged restarts the clock; heat → takeover, disk
  critical beats heat warn; null CPU/GPU on the first sample → 0.
- CPU: right after launch Vitals ran ~63% of a core for about a minute; `sample` showed that's the launch disk scan
  (vitals.diskscan thread busy, main thread idle), not the icon. After the scan: **2.0% of one core** over 60 s, 80 MB RSS;
  same as before the dials (1.7–2.6% idle on 2026-10-18), though the icon now redraws when a needle moves 1%.
- Final build installed ~15:47Z; real state logged calm (CPU ~33, GPU 10, RAM 72), 58.0 pt at window x 1035.
- Room for Claude Meter (Vinnie chose to shorten it, 2026-10-19 ~17:40Z): Claude Meter v0.9.24 drops the 5-hour % from
  its title when the week is in it; its widest form is now 169 pt. With every test title cycling, Claude Meter's left
  edge stayed at x 874+ (notch edge 848.5) and Vitals at window x 1043 (74 wide). Details in Claude Meter's HANDOFF.
- Committed and pushed to `main` as 778a602 on 2026-10-19 ~19:35Z (Vinnie typed "Save commit and push"); Claude
  Meter as 485a009.

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

## Energy fix: icon redraw loop (2026-10-19 ~23:20Z found, fixed ~23:45Z, pushed on Vinnie's "ship that new fixed version")
- Since 778a602 the `effectiveAppearance` KVO in AppDelegate re-applied the icon on every fire, and in the real menu bar
  setting the image fires it again (logged: 271 fires in 4 min with the look unchanged, ~2 per icon update): an
  endless loop. Measured before the fix: ~95% of one core with nothing open (29 s CPU in 30 s; 67 min CPU over
  5 h 26 min), Vitals top of Energy Impact and in macOS's "Using Significant Energy". Probably started at the evening
  switch to dark mode. Not the sampler, nettop (no children) or the disk scan.
- Fix: remember the light/dark match (`barLook`); redraw only when it really changes, and not for the calm template
  icon (`State.followsMenuBar`). `--status-log` logs each fire ("appearance …, (same), redrawn").
  `Disk.volume()` (CacheDelete purgeable-space lookup) now runs once a minute instead of every 2 s tick, so the
  window's free space can lag up to a minute.
- Checked: off-screen harness with a real NSStatusBarButton flipped aqua/dark/aqua: strained icon redrawn on each flip,
  calm icon never (couldn't reproduce the loop off screen; only the real menu bar re-fires). Installed; `--status-log`
  run for 4 min: CPU after the launch scan **0.37% of one core** (0.68 s over 180 s), top 0.1%, 0 idle wakeups shown;
  every fire "(same)", none redrawn. Not checked: a real light/dark switch in the menu bar (needs the system setting).

## Audit top-4 fixes (2026-10-20, branch fix/audit-top4)
- Audit + Fable review: /mnt/project-files/tool-reviews/vitals-2026-10-19/REPORT.md (0 high, 4 medium, 23 low).
  Vinnie asked for the 4 mediums, then a test run.
- 1 Folder scan removed (DiskScan.swift deleted, `bigUsers` and `--scan` gone): no page showed it since the
  stats-only cleanup, and it cost ~45 s of CPU per launch plus every 30 min with the window open.
- 2 "Today" totals: a boot time within 60 s of the stored one is not a reboot (macOS moves kern.boottime when it
  corrects the clock). A counter below its last value restarts from zero; `lastSeen` merges, so an interface down at
  midnight keeps its baseline.
- 3 Popover page released 60 s after the popover closes (reopen inside the minute stays instant).
- 4 Resting (changed 2026-10-31, see the top: now only another user's session in front rests; lid shut / locked keep 2 s):
  screens asleep, screen locked (com.apple.screenIsLocked) or session inactive → one sample a minute;
  back to 2 s with a sample at once on wake. More than 10 s between samples = a gap: null chart points, no disk/net
  rates, and the CPU/GPU 30 s busy clocks restart.
- `--selftest` (SelfTest.swift, ~25 s, no windows): baseline cases, busy clock across a sleep, and a real Sampler
  resting/waking with the gap.
- Checked on the Mac (2026-10-20 ~00:35Z, 9a55cc5): release build clean, no warnings. `--selftest` 21/21 PASS in
  19.5 s. `--dump`: valid JSON, no `disk.bigUsers`; read today 596.4 GB, written 49.8 GB (baseline 2026-10-19, boot
  unchanged, up 10 days). `--bench`: 13.4 ms per tick with process rows, 1.8 ms without (one tick, not an average),
  32 MB resident. Renders (window/popover/help light+dark, menubar) clean, no page errors. `--soak 3 window`: app
  18 → 24 MB, page 68 → 89.5 MB (live buffers filling, as before).
- Installed 00:31Z (pid 32957): first 211 s used 2.1 s of CPU (1.0% of a core), `top` avg 0.95%, 19–21 MB. The
  50–80% launch spike (the scan) is gone. tccd: only the usual launch preflights (ListenEvent, Gatekeeper), no prompts.
- Not checked on the Mac (needs the screen asleep/locked, the popover open, or a midnight): the real rest
  notifications, the once-a-minute sample while resting, the popover release (`--status-log` prints "popover page
  released"), a real midnight rollover.

## Audit efficiency chunk (2026-10-20, branch fix/audit-efficiency)
- Vinnie: "next logical chunk, then retest it all". REPORT.md items Low 1, 2, 3, 4, B, I (+ the fan guard from 9).
- Menu bar only: battery (AppleSmartBattery's whole property table) and fan (SMC) are read only while a page shows
  (once at launch, then the last reading is kept). Interface display name only when the interface changes; one
  SCDynamicStore for the app's life; one DateFormatter; "today" baseline saved every 5 min (and on quit), not 30 s.
- The unused 1-hour `history` (memory/cpu/gpu) is gone from the snapshot and DATA.md; per-process
  `compressedBytes` (task_name_for_pid per pid per tick) too. Pages never read either.
- Timer: created and rescheduled only on the sampler queue; 1 s slack with only the menu bar, 0.2 s with a page.
- nettop keeps its last totals when the window is covered, so rates come back on the first run if it was under 30 s.
  Stopped, its rates aren't handed out.
- Dials redraw only when a needle moves 2%+ or a color changes (`State.looksLike`); unchanged + no page = no main-
  thread hop at all. Tooltip / accessibility label set only when the words change.
- Opening a page pushes only a snapshot taken while a page showed (no stale process rows); the kick fills it in.
- `--selftest` adds: dial dead-band, no history in the snapshot, battery/fan present with no page.
- Checked on the Mac (2026-10-20 ~00:55Z, 37b3a6e): builds; one new warning at Sampler.swift:53 (`[weak self]` inside
  a `queue.async` holding self strongly), fixed right after by `queue.async { [weak self] in guard let self …`
  (built clean on the Mac; same behavior). `--selftest` 26/26 PASS in 21.5 s. `--dump`: no history, compressedBytes
  or bigUsers; energy has battery/fan/thermal; today totals sane. `--bench`: 12.2 ms per tick with rows, 1.1 ms
  without (was 13.4 / 1.8), 31 MB. Renders clean (Net columns, battery, fan still show). `--soak 3 window` as before.
- Installed 00:56Z (37b3a6e). 3 min of `top`: CPU avg 0.97% → 0.74% of a core (max 1.5 → 1.3), memory 20–21 →
  19–20 MB, idle wakeups too few to compare. tccd: the same 4 launch preflights, no prompts.
- Not checked (needs a real window on his screen): nettop totals kept across a brief cover-up, no stale rows on open.

## Audit usability chunk (2026-10-20, branch fix/audit-usability)
- Vinnie: "go ahead with the next chunk". REPORT.md items Low 6, 7, 8 and Fable's E.
- Quit (L6): every row carries `started` (the process start time, a string); the Quit sheet sends it back and
  `quitProcess` beeps instead of quitting if that pid now belongs to a different process (`AppDelegate.sameProcess`).
- Open at Login (L7): when macOS wants the user's OK, the menu shows "Open at Login (allow in Settings…)" with a dash,
  and choosing it opens System Settings → Login Items (`SMAppService.openSystemSettingsLoginItems`), also right after
  turning it on if macOS asks.
- Shortcut (L8): `Hotkey.registered` is false when another app holds ⌃⌥⌘V; the right-click menu then drops the ⌃⌥⌘V
  hint and shows "⌃⌥⌘V is taken by another app" (greyed). Logged with NSLog.
- ⌃-click (E) opens the right-click menu, like a right-click.
- Help (icon section) and README mention right-click / ⌃-click.
- `--selftest` adds: start-time check (same process passes, +1 tick or no time fails, rows carry it), the three
  login item states, and a test shortcut (⌃⌥⇧⌘F19) registered twice: first OK, second reported as taken.
- Not checkable without his screen: the real right-click / ⌃-click menu, the Login Items hand-off, a real Quit.
- Checked on the Mac (2026-10-20 ~03:10Z, 55775ae): 0 warnings. `--selftest` 37/37 PASS in 21.5 s; the second F19
  registration got OSStatus -9878 (eventHotKeyExistsErr). `--dump`: all 710 rows have `started`; 490 of 491 own rows a
  string (the pid-less Claude Code group is null), all 219 other users' rows null. `--bench` 14.3 / 13.9 ms with rows,
  1.2 / 1.3 without. Renders clean (help's icon text is in the bundle but below the 860 pt render). `--soak 3 window`:
  app 18 → 26 → 25.7 MB, page 67 → 92 MB.
- Installed 03:08Z (pid 51089). 3 min of `top -s 2` (89 samples): CPU 0.67% → 0.70% (max 1.7 → 2.8; `ps` 0.72% → 0.74%),
  memory 30 MB (old app, ~2 h up) → 20–21 MB (fresh). tccd: the same launch preflights (ListenEvent ×2, DeveloperTool),
  no prompts. No "shortcut not registered" line, so the installed app has ⌃⌥⌘V.

## Audit tidy-ups (2026-10-20, branch fix/audit-tidy)
- Vinnie: "do the last batch now then". REPORT.md items Low 9, 10, 11, 14 and Fable's C, D. All Mac work in the
  background (his rule, 2026-10-20): no windows, no focus, install relaunches with `open -g`.
- L9: core kinds no longer force-unwrap; odd CPU numbering falls back to "E cores first".
- C: one host port for the app's life (`hostPort`), not a new reference every tick.
- D: page data checks `isValidJSONObject` first (a NaN made JSONSerialization throw an uncatchable exception);
  bad values go out as null (`jsonSafe`) and the log says so; an encode error is logged instead of silently freezing.
- L10: app.js lost its unused helpers (summary, fix, busiest, biggest, topApp, cpuState, hot, batteryLow, diskLow,
  spark, trend, avg, treemap, worstRatio), including the two that put unescaped names into HTML. Pages checked in
  headless Chromium with sample.js: same text, no errors.
- L11: build.sh stamps CFBundleVersion with the commit count, so About shows "Version 0.1.0 (N)".
- L14: two apps with the same name get "group:name" and "group:name-2" (oldest pid keeps the plain id).
- `--selftest` adds: NaN → null in page data, unique group ids, no port-reference pile-up, counters still read.
- Checked on the Mac (2026-10-20 ~03:40Z, bc2f940), all in the background: 0 warnings; CFBundleVersion 51 (= commit
  count). `--selftest` 42/42 PASS in 21.5 s. `--dump`: 644 rows, no duplicate ids (14 groups), no field newly null,
  all own rows have their numbers. No removed app.js helper is still referenced. `--bench` 16.6 / 16.4 ms with rows
  (was ~14; maybe the isValidJSONObject walk, only while a page shows), 1.2 without. Renders clean; `--soak 3 window`:
  app 18 → 26 → 24.4 MB, page 81 → 103 MB.
- Installed 03:38Z with `open -g` (pid 56995); the front app (Claude) didn't change. 3 min of `top -s 2`: CPU 0.64% →
  0.37% (ps 0.69% → 0.42%), 21 → 17–18 MB. tccd: the usual launch preflights, no prompts; no "snapshot" / "page data"
  log lines.
- Audit fix order (REPORT.md 1–8) is done. Not done (not in the order): L12 second-display colors, L13 signing,
  Fable F (Help alone runs full sampling), G (4 KB path buffer per pid), H (popover takes focus).

## Audit fixes (2026-10-23, branch fix/audit-2026-10-23)
- Vinnie: "fix everything" from /mnt/project-files/tool-reviews/2026-10-23/vitals.md (0 High, 1 Medium, 9 Low), "making
  sure you are testing everything". All 10 fixed, in the report's order, one commit per group. Nothing skipped.
- **M1 charts after a sleep or lock** (Sampler.swift, app.js): more than 10 s between samples now adds one null point per
  2 s away (`Sampler.gapSlots`, at most 150) instead of one, so pre-sleep points sit where they really were or slide off,
  and hover times are right. Resting (one sample a minute) adds 30 per sample, so an hour locked is a full empty chart.
  `V.now` falls back only to the newest point, never past a null: disk/net/energy read "–" on the waking sample.
- **L nettop stale rates** (Processes.swift): rates carry the time they were worked out; `rates()` hands out none over 30 s old.
- **L rest at launch + L lock notifications** (AppDelegate.swift): lock/unlock observers use `.deliverImmediately`
  (selector API, hop to main). At launch `restingAtLaunch` checks CGSessionCopyCurrentDictionary (screen locked, session
  not on console) and CGDisplayIsAsleep(main display) and rests right away.
- **L unlock double sample** (Sampler.swift): a timer tick or kick under 0.5 s after the last sample never takes a full
  sample (`sampleIfDue`), in either order. If the last sample was taken without a page (stale rows) and a page now wants
  rows, it gets the last snapshot with fresh process rows and energy impact only (`withFreshRows`; their rates run from
  the last rows sample), so CPU, disk and network are never measured over a few ms. (First version only skipped when the
  last sample already had rows; the review found the unlock order where the rest-end sample comes first slipped through.)
- **L clock change resets "today"** (Devices.swift): reboots are detected by `kern.bootsessionuuid` (stored as `session`
  in `dailyBaseline`); kern.boottime moves with the clock, so it's only the fallback (60 s) for a baseline saved without an id.
- **L time zone** (Devices.swift, Sampler.swift): the day and snapshot-time formatters re-zone to `TimeZone.current` when
  it changes, and `NSTimeZone.resetSystemTimeZone()` runs on the existing once-a-minute volume check (no new wakeups).
- **L `--dump` NaN** (Dump.swift): goes through `AppDelegate.encodeData` (the pages' NaN-safe encoder) with pretty/sorted options.
- **L shortcut taken** (Hotkey.swift, AppDelegate.swift): besides a failed registration, the right-click menu now checks
  macOS's own enabled shortcuts (CopySymbolicHotKeys) each time it opens: "⌃⌥⌘V is taken by a macOS shortcut". The
  list's modifiers should be Carbon flags (as MASShortcut / ShortcutRecorder compare them); `carbonModifiers` also
  accepts Cocoa flags (as com.apple.symbolichotkeys.plist stores them) and drops fn / caps lock, so either works. Still not
  detectable: another app's non-exclusive Carbon registration or an event tap (no API for it).
- **L same-named apps** (Processes.swift): `ProcessSampler.groupIDs` keeps each pid's group id across samples; a new copy
  never takes an id another pid had last sample. So when the oldest copy quits, the other keeps "group:name-2".
- Tested here (Linux): `node scripts/test-pages.js` (new, headless Chromium, fake snapshots): 17/17 pass after; 5 fail
  before the app.js fix (V.now, window disk/net/energy readouts, popover readouts). `node --check` on app.js, sample.js
  and the pages' scripts. Swift 5.10.1 (Linux toolchain, scratch): `swiftc -parse` on every file; the pure-logic code
  copied verbatim into a scratch harness (DailyBaseline, NetTop, groupIDs/uniqueID, gapSlots, carbonModifiers,
  restingAtLaunch, encodeData/jsonSafe, sampleIfDue/withFreshRows on a fake sampler, with stubs for Sysctl and the
  Darwin-only calls) type-checks and passes 39/39, including both unlock orders. AppKit/Carbon/CoreGraphics code
  (observers, CopySymbolicHotKeys, CGSession) and SelfTest.swift are only parsed: they need the Mac's build.
  New `--selftest` cases for every Swift fix (listed below). An independent review of the diff found the unlock-order
  hole, fixed as above.

## Mac test plan (audit 2026-10-23)
All in the background (Vinnie's rule): no windows on his screen, no focus grabs, install relaunches with `open -g`.
1. `git fetch && git checkout fix/audit-2026-10-23`, `scripts/build.sh` (not --install yet). Expect 0 warnings.
2. `~/Library/Caches/VitalsBuild/Vitals.app/Contents/MacOS/Vitals --selftest` (~25 s, no windows). Expect all PASS
   (up to 78: 42 before + 36 new; two hotkey checks only run when the system list has entries; "the login session's
   state" and "macOS's own shortcuts" depend on the Mac). New checks: baseline clock moved 2 h on / 5 h back, new boot session, relaunch,
   upgrade from a baseline without an id, "this Mac has a boot session id", day and snapshot time in two zones;
   quit/rest launch-state rules and "the login session's state can be read"; hotkey "macOS's own shortcuts can be read"
   and a listed one matches, Carbon/Cocoa modifiers (3), Space shortcuts read with modifiers; `--dump` NaN; rows group
   ids (3); charts gap slots; nettop (4); kick (5, incl. the unlock order: same snapshot time and disk rate, fresh
   energy impact); sampler "the
   stretch is padded to its real length". If "login session's state" or "macOS's own shortcuts" fail only because the
   command ran outside his login session, rerun from a Terminal in his session before treating it as a bug.
3. `Vitals --dump | python3 -m json.tool > /dev/null` (valid JSON); `time` still has his offset; `sysctl kern.bootsessionuuid`
   prints a UUID; `defaults read com.vinnie.vitals dailyBaseline` gains a `session` after ~5 min of the installed app.
4. Renders: `--render window`, `popover`, `help` light/dark and `--render window out.png dark --warm 40`; no page errors.
   `--soak 3 window` as before (app ~25 MB, page ~100 MB).
5. Install (`scripts/build.sh --install`, relaunches with `open -g`). Resting check, as for the earlier `--status-log`
   runs: quit the installed copy, start the build with `open -g -n <app> --stdout /tmp/vitals-rest.log --args --status-log`
   (it sits in the menu bar like the real one; quit it after and relaunch the installed one with `open -g`). Ask Vinnie
   to lock the screen (⌃⌘Q) for a minute with the screens on, then unlock: the log must show "rest locked on → once a
   minute" at the lock and "rest locked off" at the unlock, with Vitals NOT the active app (the .deliverImmediately fix).
   Then start a test copy while the screen is locked (`sleep 20; open -g -n …`, lock within 20 s): the log shows "rest
   locked on" right at launch.
6. Charts after a gap (needs his window, so only when he opens it himself): after the lock above, the window's charts show
   the lock as an empty stretch of the right length, hover over the last point before it says the real time ago, and
   the disk/net big numbers show "–" for one tick. No tall spike in disk/net right after the unlock.
7. CPU: 3 min of `top -l 0 -s 2 -pid $(pgrep -x Vitals)` with only the menu bar: about the same as before (0.4–0.7%).
8. Optional: hold ⌃⌥⌘V in System Settings → Keyboard Shortcuts (e.g. assign it to a Services item), right-click the
   icon: "⌃⌥⌘V is taken by a macOS shortcut". Undo it after.

## Deploy (audit 2026-10-23)
- Merge fix/audit-2026-10-23 into main only on Vinnie's OK, then `scripts/build.sh --install` on the Mac (background, `open -g`).
- First launch after install: the stored baseline has no boot session id, so the old 60 s boot-time rule decides once;
  the id is saved with the next save (within 5 min, or on quit). No reset of today's totals expected.

## Dark mode app icon (2026-10-23, branch icon/dark)
- Vinnie asked for a dark version of the app icon and picked "Graphite" from the mockups
  (https://claude.ai/artifact/RsKpvdyvdnXcfgdfVnyDLe): the Vitals window's dark grays, light needle, amber #EEA929.
- `icon/make-icon.swift` draws light + dark full icons and the gauge alone (scaled to the 1024 Icon Composer canvas).
  `icon/Vitals.icon/icon.json` (hand-written Icon Composer file): tile gradient + gauge layer, each with a dark
  specialization. `build.sh` compiles it with `xcrun actool` into Assets.car and adds CFBundleIconName; AppIcon.icns
  stays for older macOS. `scripts/icon-preview.sh` renders both looks with Icon Composer's ictool, off screen
  (NSWorkspace's icon follows the Mac's own mode, so it can't show the light icon while the Mac is dark).
- Checked on the Mac (2026-10-23, Xcode 27.1): actool compiled icon.json first try; Assets.car has Aqua, DarkAqua and
  Tintable renditions. ictool: light tile #E7E5E0 / hub #5C5A56 (today's icon: #EBEAE4 / #5C5A55), dark tile #2F2F31 /
  hub #EAEAED. Finder shows the graphite icon on the dark Mac.

## Open decisions
- Privileged helper for root processes' numbers (needs an admin prompt once)?

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
