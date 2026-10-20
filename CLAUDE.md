# Vitals

See README.md, HANDOFF.md, BRIEF-mac.md and DATA.md.

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
