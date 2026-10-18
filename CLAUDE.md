# Vitals

See README.md, HANDOFF.md, BRIEF-mac.md and DATA.md.

## Lessons
- `nettop` without `-n` does reverse DNS lookups and takes ~5 s per run; with `-n` it's ~0.03 s.
- Running as the user, `proc_pid_rusage` / `PROC_PIDTASKINFO` fail for root and other users' processes (kernel_task, WindowServer…); Activity Monitor and `top` (setuid root) can see them, Vitals can't.
- The `claude` binary also runs its built-in tools (ugrep) under another argv[0]; tell sessions apart by argv[0], not by the executable path.
- In zsh, `log` is a shell builtin: `log show` / `log stream` silently do nothing useful. Use `/usr/bin/log`.
- Walking ~/Library/Caches touches Apple Music's caches and makes macOS ask for Media & Apple Music access; skip Apple's caches. Ad hoc signing makes macOS forget privacy answers on every rebuild.
- Never open windows on Vinnie's screen to test: use `--dump` and `--render` (borderless window parked at -40000,-40000, activation policy .prohibited).
