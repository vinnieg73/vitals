# Vitals — handoff

_Last updated 2026-11-10 by Claude: the Claude Code model dots are now each session's own model (shipped, below).
The review items Vinnie approved ("go ahead with all changes and follow your recommendations") are being built next._

## What it is
A menu bar app for Vinnie's Mac that shows what Activity Monitor shows with every stat up front: three dials in the menu
bar (CPU, GPU, RAM), a drop-down with six small charts and "Memory by app", and a full window with the same charts
(5 min / 1 hour / 12 hours) plus every process. README.md says how it works and how to build and test it; DATA.md is
the data the Swift side sends the pages; CLAUDE.md holds the lessons learned; docs/HISTORY.md is the dated log of
every change before today.

## Where things stand
- Repo: PRIVATE github.com/vinnieg73/vitals, branch `main`, pushed.
- Installed: /Applications/Vitals.app, built from the model-dots commit. Opens at login by itself (Login Items shows it enabled).
- Everything Vinnie has asked for is shipped. Nothing is half done.

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

## Waiting on Vinnie
1. (Done 2026-11-10: he typed OK to commit, push and install.)
2. The review's list of things that were his call; on 2026-11-10 he said "go ahead with all changes and follow your
   recommendations", so these are being built:
   - The heat / low-disk icon uses a colored dot. His later rule (2026-10-28) is no dots or badges for warnings.
   - The menu bar dial and the drop-down can disagree for a moment about "strained": the icon lets go of amber at
     pressure 65% (so it doesn't flicker), the pages at 70%. On the 12-hour chart this shows as stripes when pressure
     hovers at the line.
   - System processes (root's, WindowServer) show "–" for User, memory and CPU. The User column can be filled without
     an admin prompt; the numbers need a privileged helper (one admin prompt).
   - The version has said 0.1.0 since day one (About shows "0.1.0 (build)").
   - Old files: design/ and docs/mockups/ (3.4 MB of first-round mockups), BRIEF-mac.md, the stale renders/ folder
     on the Mac (8 MB, not in the repo), and 10 merged branches (4 local, 6 on GitHub).
3. Still offered: keep the 1-hour / 12-hour chart history across restarts (today it starts over with Vitals).
4. Two checks only he can do: open the drop-down after the lid has been shut a while (charts should have no gap),
   and a screenshot of the Energy row while plugged in.

## Never checked on his real screen
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
- Commit, push and install need his own typed words. Update README, this file and Help (Resources/help.html) with
  every change, before the commit. All checks green first.
- Test a new option on the cache build (`~/Library/Caches/VitalsBuild/Vitals.app`), never on the installed app.
- After any change to the menu bar icon, measure CPU again in both a light and a dark menu bar (the 2026-10-19 redraw
  loop only showed in the real menu bar).

## Gotchas
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
