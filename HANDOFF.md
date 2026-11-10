# Vitals — handoff

_Last updated 2026-11-10 by Claude: version 1.1 is shipped and installed. Today, in order: version 1.0 (the accurate
Claude Code model dots and the six review items Vinnie approved), a layout fix for the window (cut-off Load numbers,
crowded Energy caption), and version 1.1 (the drop-down's Disk row says how much is free; the install script
retries its last step)._

## What it is
A menu bar app for Vinnie's Mac that shows what Activity Monitor shows with every stat up front: three dials in the menu
bar (CPU, GPU, RAM), a drop-down with six small charts and "Memory by app", and a full window with the same charts
(5 min / 1 hour / 12 hours) plus every process. README.md says how it works and how to build and test it; DATA.md is
the data the Swift side sends the pages; CLAUDE.md holds the lessons learned; docs/HISTORY.md is the dated log of
every change before today.

## Where things stand
- Repo: PRIVATE github.com/vinnieg73/vitals, branch `main` only, pushed. Tags `v1.0` (3b3e107) and `v1.1`.
- Installed: /Applications/Vitals.app, version 1.1, built from the commit tagged `v1.1`. Opens at login by itself
  (Login Items shows it enabled).
- Everything Vinnie has asked for is shipped. Nothing is half done.
- Checks on the final tree (2026-11-10, cache build): build 0 warnings, `--selftest` 176 pass, page tests 92 pass,
  window / popover / help / menubar rendered light and dark with no page errors, an unknown option (`--scan`) exits 2.
  (At the v1.0 tag: the same, with 34 page tests.)

## 2026-11-10 version 1.1: free space in the drop-down, install retry (shipped)
Vinnie saw the amber drive in his real menu bar and asked what it meant (the disk was under 10% free). The drop-down
never showed free space, so it couldn't say why the icon changed. Offered; he said "go for it".
- **Drop-down, Disk row: a third line "47.5 GB free"** under the two speeds, small and gray like the other rows'
  third lines ("Swap ...", "14 cores", "Battery full"). Amber when the app says the disk is low, red when critical:
  the color is `strain.disk` from the feed (`Vitals.strainCls`), the same verdict that puts the drive in the menu
  bar, so the two can't disagree (in under 10% free, out at 12%; red under 3%, out at 4%). The page has no
  threshold of its own. Numbers only. The number is the window's Free (`F.sizeParts` in app.js, now shared by both
  pages: one decimal in GB, TB from 1,000 GB). Rows are still 52 px and the drop-down the same length in every
  state; with no free-space number in the feed the row is the two speeds, as before.
- **sample.js** shows all three states: plain (calm), `?disk=warn`, `?disk=crit`; it copies the app's rule for
  `strain.disk` like it does for memory.
- **build.sh --install** retries `open -g` (up to 5 tries, 2 s apart) and then ends with an error unless exactly
  one Vitals is running from /Applications. Cause: `open` failed once with error -600 right after the old copy
  quit, leaving the new build installed but nothing running. The retry logic was run with fake `open` / `pgrep`
  (works first time, fails twice then works, fails 5 times, nothing running, two copies): right result each time.
- Version 1.1, build 101 (`Support/Info.plist`), tagged `v1.1`. Next is 1.2 = 102.
- Page tests: 13 new (92 in all), light and dark: the line is there and gray when calm, amber on warn, red on
  critical, no color of its own when the app says ok or sends no verdict, never cut off or out of its row with
  1.82 TB / 999.9 GB / 7.92 TB beside 999.9 MB/s, absent without a number, rows and length unchanged in every
  state; and the three sample states. Looked at: the real drop-down render with this Mac's real numbers
  ("47.5 GB free", amber: 9.6% free) light and dark, and the calm / warn / critical samples in both.
- Help: the icon section says the menu's Disk row shows free space in the same color. DATA.md: who reads `strain`.

## 2026-11-10 window layout fix (shipped)
Vinnie sent screenshots of the installed 1.0 under heavy load (window about 1100 pt wide). Two flaws in the window's
stats, plus what the same check found elsewhere. Nothing else about the look changed: the two lists of small stats
are pixel for pixel where they were.
- **Load: all three numbers always show** (it read "17.9  21.1  …"). Cause: every row of a list shared one label
  column as wide as the longest label ("Processes"), so "Load" wasted room. Now each row is its own line (`.kv div`),
  so a value gets all the room its own label leaves. A load of 100 or more drops its decimal ("118  121  125").
- **Energy: "Power draw, whole Mac" no longer runs into "Battery".** The first column (the big number and its
  caption) is wider: 120 px, 128 px in the narrow layout (window 1180 or narrower); it was 114. The room comes out
  of the chart (6 px, 14 px narrow), so the gap is 19 px at every width for every caption (was 5 px narrow, 13 wide).
- **Big numbers are shortened, never cut** (found by the same check): sizes read in TB from 1,000 GB; the four
  totals for today (read, written, received, sent) drop the decimal from 100 GB; swap has one decimal from 100 GB;
  "Swapped out" reads in TB from 1,000 GB. Vinnie's Mac shows one of these today: "Read today 949 GB" and
  "Written today 172 GB" where it said 949.3 and 172.4 (the old forms had 2 px to spare beside "Written today").
- **Process table** (the real render showed "38.9 MB…" under Net out): Net in / Net out are 86 px (were 80) and
  User is 130 px (was 118, "_windowserver" was cut to "_windowserv…"); the 24 px come out of the Process name
  column. A speed drops its decimal from 100 MB/s, CPU % and energy from 1,000. At the minimum width the Claude
  Code row still fits 23 model dots (was 26).
- A speed of 999.95 MB/s or more reads "1.0 GB/s", not "1000.0 MB/s" (app.js `F.rate` / `F.rateParts`, both pages).
- Page tests: 45 new (79 in all). At 1100, 1181 and 1680 px, light and dark: no stat cut off or crowded with the
  sample feed and with huge numbers (plugged in, on battery, no battery); the Energy caption's gap; the Load cell
  from the screenshot; the table's numbers, a system user's name and 14 model dots. One test plants a too-long
  value and caption to prove the check can fail. All of the fit tests fail on the page as it was at v1.0.
- Not checked in the real web view at 1100 px (`--render` draws 1280 only): there the tests' Chromium stands in.
  The render at 1280 with the Mac's real numbers (loads 32 / 22 / 21) is right, light and dark.
- Worth a look by Vinnie: the window at its smallest size under load (Load's three numbers, the Energy caption).

## Shipped 2026-11-10 (commits, oldest first)
- 15147ad the model dots are each session's own model
- 475e953 heat / low-disk icon with no dot
- b281598 one amber / red verdict for the icon and the pages
- 8a3aaa5 User column for system processes; Quit only for your own
- bca07f7 the 1-hour and 12-hour charts survive a restart
- d271be2 mockups, the original brief and the merged branches removed
- 0a063de version 1.0
Details of each are in the two sections below.

## Vinnie still owes a look (only he can see these on his real screen)
1. The drop-down's Disk row: "N GB free" under the speeds, amber while the drive icon shows.
2. The window at its smallest size under load: Load's three numbers, the Energy caption.
3. The charts after a restart: quit Vitals and open it again (or restart the Mac), then open the window on 1 hour
   or 12 hours. The old history should still be there, with a gap for the time Vitals wasn't running.
4. The drop-down after the lid has been shut a while: the charts should have no gap.

Seen 2026-11-10 on his real menu bar (his screenshot, he asked what it meant): the new low-disk icon, an amber drive
with no dot. The heat icon and the red (critical) versions have not come up.

Seen 2026-11-10, in a screenshot of the drop-down Vinnie sent a few minutes after the install of 1.0:
- The model dots: 12 dots, 7 pink (Fable) and 5 orange (Sonnet). Checked right after against each running
  session's own transcript: 7 on Fable, 5 on Sonnet, every dot right. The five orange ones have only ever answered
  as Sonnet. (A session that has not answered yet is gray.)
- The Energy row while plugged in: "38.4 W for Mac", "Fan 3,510 rpm", "Battery full" in the drop-down; "On 68 W
  charger" and "To battery 0 W" in the window. As designed.
- The Memory chart had a few short amber stretches while the number was white: the per-point strain level
  (`live.memStrain`), the same verdict the menu bar's RAM dial showed at those moments.

## 2026-11-10 model dots (shipped)
Vinnie: "the dots that show what model is running need to be accurate. they are currently wrongly showing sonnet when
i know those threads are running fable currently". Cause: the model was guessed per folder (the newest transcript in
the folder, the last "model" text in it), so every session sharing a folder got one dot, and a subagent's line could win.
- Now `SessionModels` (Processes.swift) reads each session's own files: `~/.claude/sessions/<pid>.json` (checked
  against when that pid really started) names the session's own transcript, and the model is the latest main-chain
  assistant line in it (no subagent or "<synthetic>" lines). Full rule in DATA.md.
- Never a guess that could be wrong: with no session file, the folder's newest transcript only counts for the one
  session in that folder, and only if written after it started. Otherwise the model is unknown and the dot is gray
  (the session is still listed and counted).
- Cost is flat: rechecked every 20 s, and a transcript that grew is read only from where the last read ended (they
  reach hundreds of MB). `--dump --bench` is the same before and after (33 to 38 ms per tick on a busy Mac).
- Checked 2026-11-10 on the cache build: every running session's dot compared with its own transcript, all match
  (the Fable ones that showed Sonnet now show Fable). Selftest: 17 "sessions:" checks on made-up files in a temp
  folder. Page tests: a session with no model is still counted and drawn gray (window and popover).

## 2026-11-10 review items Vinnie approved (built after the model dots)
- **Heat / low-disk icon, no dot.** The thermometer or drive that takes over from the dials is itself amber, red
  when critical, like a strained dial (`StatusIcon.symbol`). The colors are fixed, so it reads the same on a light
  and a dark menu bar. The item's width is unchanged (the dials' 58 pt picture; 64 pt with the button's padding).
  The icon is still only set when its state changes (`deliver`), and the light/dark observer still only redraws on
  a real flip. Help's two pictures were redrawn (`--render menubar`). Selftest: 6 "icon:" checks (they run last:
  making a real status bar button lets AppKit nap the timers the sampler checks wait on).

- **Icon and pages agree on amber / red.** `StatusIcon.Judge` (with its hysteresis: in at pressure 70, out under
  65, and so on) now runs once per sample inside the sampler and its answer goes out in the snapshot: `strain`
  (memory, swap, cpu, gpu, heat, disk) plus a level per chart point (`live.memStrain`, `long.memStrain` = the
  minute's worst). The menu bar item is drawn from that block (`StatusIcon.State(snapshot:)`) and the pages only
  draw it: app.js no longer has thresholds of its own. So the memory number, the swap number, the chart's line and
  hover, and the 12-hour chart (no more stripes at the line) change color at the same moment as the icon. sample.js
  carries the same fields (it copies the memory rule for its fake data). Nothing else on the pages changed.
  Selftest: 14 "strain:" checks, 2 sampler checks, 1 long-history check. Page tests: 8 new.

- **User column filled for system processes.** Root's, _windowserver's and other users' processes now show their
  owner (`ProcessSampler.owners`: sysctl kern.proc.all, no admin rights, no helper; names cached). Their memory and
  CPU still read "–" (that needs a privileged helper, not built). Because "no user" used to be what kept those rows
  from being quit, the window's `quittable()` now needs the row's user to be the user Vitals runs as (`host.user`
  in the feed); root's, other users', an unknown user's, pid 1 and Vitals itself are never offered. Swift's
  `quitProcess` still checks the uid itself. Selftest: 7 "users:" checks and 1 sampler check. Page tests: 4 new.

- **The 1-hour / 12-hour charts survive a restart.** `LongHistory` saves to
  `~/Library/Application Support/Vitals/history.json` (versioned, written in one step; about 60 KB): at most every
  5 minutes from the sampler, on quit and before sleep (`Sampler.saveState`). Loaded at launch; points 12 hours old
  or more are dropped, and the time Vitals wasn't running is empty minutes, so the charts show a gap, not a line.
  A missing, damaged or other-version file is ignored. The drop-down's 5 minutes stay in memory. Only the installed
  copy started the normal way uses the file (`AppDelegate.historyFile`); test builds, `--selftest` and every other
  option keep history in memory. `kill` / build.sh's pkill now quits Vitals the normal way (a SIGTERM handler calls
  terminate), so an install saves the charts and the "today" baselines too. Selftest: 16 "history:" checks on temp
  files. Page test: a gap in the 12-hour chart is two separate lines.

- **Old files and branches removed.** `design/`, `docs/mockups/` and `BRIEF-mac.md` are out of the repo (nothing
  but the dated log in docs/HISTORY.md mentioned them; they stay in git history up to commit bca07f7). The local
  `renders/` folder was emptied (still gitignored, still where README's `--render` example writes). The merged
  branches are deleted, each proven an ancestor of origin/main first: local fix/audit-efficiency, fix/audit-tidy,
  fix/audit-top4, fix/audit-usability; on GitHub those four plus fix/audit-2026-10-23 and icon/dark. Only `main` is left.

- **Version 1.0.** `Support/Info.plist` says 1.0 with build number 100 (the rule shared with Claude Meter: two
  numbers, build = major × 100 + minor). 1.1 = 101 followed the same day. build.sh no longer stamps the commit count and refuses a
  version / build pair that doesn't fit. About reads the bundle and shows "Version 1.0" (no build number in
  brackets). Tagged `v1.0`. Selftest: 4 "version:" checks.

## 2026-11-10 review (shipped in 2204b93)
Vinnie: "Read this entire project and find everything that's broken, inconsistent, inefficient, or no longer needed.
Fix what you're sure about and list the rest for me to review." Every tracked file was read. Nothing he would see
changes: the pages draw pixel for pixel the same (checked, below).

Fixed:
- **An unknown option can't start a second menu bar copy.** `Flags` (main.swift): any `--option` Vitals doesn't know
  prints the known ones and exits 2. (2026-11-05: `--login-status` on an older build fell through and put two icons
  in the menu bar.) New options must be added to `Flags.known`. Selftest: 3 "flags:" checks.
- **Fan**: when the Mac reports fans but none can be read, the feed says unknown (the fan line is left out) instead
  of 0, which the pages show as "Fan off".
- **Less in every update** (the pages never read these): per-process `idleWakeupsPs` (about 700 rows every 2 s while a
  page shows), `energy.chargerW`, and the plugged-in "time left" estimate (the window shows "To battery" there since
  2026-11-05). `minutesLeft` is now null while plugged in. Selftest: "nothing in the snapshot that no page reads".
- **Unused code out**: `Sampler.latestSnapshot` and its lock, `GPU.utilization`, two unused memory counters; in the
  pages `F.dash`, `F.dgb`, `F.rateZero`, `lastNum`, `Vitals.reveal`, Help's old gauge script, and the CSS for the
  meters, hatches, tiles and status dots the October redesigns removed (app.css 6.8 KB → 5.2 KB).
- **sample.js** (the fake feed a browser gets) no longer carries the 1-hour history, the folder scan or the charger
  total that the real feed dropped in October. build.sh now leaves it out of the app (the app never loads it, and
  fake numbers must never be able to show in the real one).
- **build.sh** stops with an error if a page is missing; the placeholder page from before the pages existed
  (Support/placeholder.html) is gone.
- **`--soak window`** now turns on what the real window turns on (per-process network and the 12-hour charts).
- **Docs**: DATA.md no longer describes the removed 1-hour history, says `quitProcess` sends `started`, lists the
  `started` field, and says a gap is "another user's session", not "screens asleep" (true since 2026-10-31). README's
  layout lists every file. BRIEF-mac.md is marked as an out-of-date record. This file went from a 58 KB log to this
  page; the log is docs/HISTORY.md, unchanged. The second copy of the two menu bar pictures (docs/shots/
  menubar-states-*.png, byte-identical to the ones in Resources/ that Help shows) is gone.
- Stale comments (the resting rule in Sampler, two others).

Checked:
- Pages, in the cloud with headless Chromium: `node scripts/test-pages.js` 17/17 before and after; 14 screenshots
  (window at 5 min / 12 hours with a hover / a row selected / `?gaps` / `?fresh=12`, popover, Help; light and dark)
  are pixel-identical before and after; every CSS color still used is defined and none is left unused.
- Mac (2026-11-10, cache build; committed 2204b93, pushed, installed to /Applications): build 0 warnings, --selftest 108/108 pass, page tests 17/17, renders OK light and dark, unknown flag exits 2.

## Never checked on his real screen
The colored heat icon, the red versions, and a light/dark switch while the colored icon shows (it is only set when
its state changes, but the 2026-10-19 redraw loop only showed in the real bar). The amber drive was showing in
his real (dark) menu bar on 2026-11-10 with normal idle CPU: 0.5 to 0.9% of one core over 30 s.
From older work (details in docs/HISTORY.md): a real light/dark switch with a strained icon showing; the drop-down's
page being released a minute after it closes; a real midnight rollover of the "today" totals; lock/unlock with the
window open (charts show the gap at its real length); the window page's memory after hours open (it crept ~1 MB/min
in a 6 minute off-screen soak).

## Decisions Vinnie already made (don't re-offer)
- Stats only: no headline sentences, verdicts or tips on the pages. Help keeps the explanations.
- Menu bar: icon only, never text, one fixed width (58 pt), three dials. No battery in the icon or the drop-down
  (macOS shows it). RAM needle = memory used %.
- Swap is judged by size (45% / 75% of RAM), never by how full the swap files are.
- Sampling stays at 2 s (he declined 5 s), also with the lid shut or the screen locked.
- The drop-down's charts stay at 5 minutes; the longer ranges are in the full window only.
- Vitals opens at login by itself; the menu's Open at Login is the off switch.

## Working rules
- Everything on his Mac runs hidden: no windows, no focus, `open -g`. Test with `--dump`, `--selftest`, `--render`,
  `--soak` and `node scripts/test-pages.js`; ask him for screenshots.
- Commit, push and install need his own typed words. Update README, this file, DATA.md and Help
  (Resources/help.html) with every change, before the commit. All checks green first.
- Versions: two numbers, build = major x 100 + minor (1.1 = 101). Bump `Support/Info.plist` for each release and
  tag it `v1.1`; build.sh refuses a pair that doesn't fit.
- Test a new option on the cache build (`~/Library/Caches/VitalsBuild/Vitals.app`), never on the installed app.
- After any change to the menu bar icon, measure CPU again in both a light and a dark menu bar (the 2026-10-19 redraw
  loop only showed in the real menu bar).

## Gotchas
- `scripts/build.sh --install` once stopped at its last step with "_LSOpenURLsWithCompletionHandler() failed with
  error -600" (2026-11-10): the new copy was in /Applications but Vitals was NOT running. The script now retries
  and checks that exactly one copy runs; if it still ends with an error, nothing may be running: read the message.
- Running as the user, macOS won't give numbers for root's and other users' processes: memory and CPU show "–" and
  they sort last. Their User column is filled (2026-11-10).
- Ad hoc signing gives every build a new identity, so macOS forgets privacy answers after a rebuild. Vitals asks for
  nothing today. An "Apple Development" identity is in the keychain, but signing with it may pop a password dialog.
- Don't run `memory_pressure -l/-p` (they create real pressure). `nettop` needs `-n`. In zsh `log` is a builtin: use
  `/usr/bin/log`.
- A Mac without a battery has no watts: the Energy charts fall back to the unitless energy score, and the 12-hour
  Energy chart is mostly empty (the score is only read while a page shows).
- `--status-log --status-test` runs a real second copy in the menu bar: quit the installed one first, kill the test
  copy after, relaunch the installed one with `open -g`.
