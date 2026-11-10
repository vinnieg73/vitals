# Vitals

See README.md (what it is, build, test), HANDOFF.md (where things stand now) and DATA.md (the feed the pages get).
docs/HISTORY.md is the dated log of older changes. (The original brief, BRIEF-mac.md, and the first-round mockups in
design/ and docs/mockups/ were removed 2026-11-10; they are in git history up to commit bca07f7.)

## Lessons
- `nettop` without `-n` does reverse DNS lookups and takes ~5 s per run; with `-n` it's ~0.03 s.
- Running as the user, `proc_pid_rusage` / `PROC_PIDTASKINFO` fail for root and other users' processes (kernel_task, WindowServer…); Activity Monitor and `top` (setuid root) can see them, Vitals can't.
- The `claude` binary also runs its built-in tools (ugrep) under another argv[0]; tell sessions apart by argv[0], not by the executable path.
- In zsh, `log` is a shell builtin: `log show` / `log stream` silently do nothing useful. Use `/usr/bin/log`.
- Walking ~/Library/Caches touches Apple Music's caches and makes macOS ask for Media & Apple Music access; skip Apple's caches. Ad hoc signing makes macOS forget privacy answers on every rebuild.
- Never open windows on Vinnie's screen to test: use `--dump` and `--render` (borderless window parked at -40000,-40000, activation policy .prohibited).
- Every Mac build, test and install runs in the background (Vinnie, 2026-10-20: "you keep taking control of my computer"): no focus grabs, no foreground launches; relaunch with `open -g` (build.sh does).
- A `variableLength` status item that changes width re-lays out the menu bar and slides icons in and out from behind the notch. Fixed `length`, set once.
- NSStatusItem Preferred Position values on macOS 27 are not screen coordinates and can't be seeded reliably; only autosaveName plus a user ⌘-drag.
- The "biggest space users" folder scan was removed 2026-10-20 (no page showed it; it cost ~45 s of CPU per launch). Don't bring it back without a page that shows it.
- `kern.boottime` moves by a second or so when macOS corrects the clock (often after a wake): never treat an exact boot-time change as a reboot.
- KVO on a status button's `effectiveAppearance` fires again when you set its image: redraw only when the light/dark match really changes, or it loops (~95% of a core, 2026-10-19). An off-screen button doesn't show this; only the real menu bar does.
- Popover sub-lines must stay short: "Battery 76% · Fan 2,543 rpm" on one line ran into the strip chart. Check the widest values headless before shipping a new line.
- Node flags can take a separate value (`--conditions node`): when finding the script a runtime runs, take the first argument that looks like a path, not the first non-flag.
- zsh doesn't split words on `set -- $v` (a loop over "page file mode" strings wrote `docs/shots/.png`): spell each command out, or use bash.
- Never run `/Applications/Vitals.app/Contents/MacOS/Vitals <flag>` to test a new flag before installing: an older build ignores unknown flags and starts a second menu bar copy (two icons, 2026-11-05). Test flags on the cache build (`~/Library/Caches/VitalsBuild/Vitals.app`), then install. Builds from 2026-11-10 on refuse an option they don't know (`Flags` in main.swift) instead of starting; add a new option to `Flags.known` or it exits with "unknown option".
- The window's stats cells and table columns are fixed width, so a number that can grow gets cut off ("17.9  21.1  …" for three two-digit loads, "38.9 MB…" in Net out; 2026-11-10). A new stat or number format needs its widest value added to `heavy()` in scripts/test-pages.js, and a shorter form when it doesn't fit; Chromium and the real web view differ by a pixel or so, so leave 2 px or more.
- `open -g` failed once with error -600 right after the old copy was killed (2026-11-10), leaving the new build installed but not running. build.sh now retries it and ends with an error unless exactly one Vitals runs from /Applications; if an install still ends with an error, read it (nothing may be running).
