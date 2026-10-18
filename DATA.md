# Vitals data feed (Swift → pages)

The three pages in Resources/ (window.html, popover.html, help.html) are plain HTML/JS shown in WKWebViews.
Swift samples the Mac every 2 seconds and calls, in every live web view:

    Vitals.update(<snapshot JSON>)

Pages talk back with `window.webkit.messageHandlers.vitals.postMessage({action, ...})`:

| action          | extra fields        | Swift does                                                        |
|-----------------|---------------------|-------------------------------------------------------------------|
| `openWindow`    |                     | show the main window, close the popover                           |
| `openHelp`      | `section?` (string) | show the Help window (optionally `Vitals.scrollTo(section)`)      |
| `quitApp`       |                     | quit Vitals                                                       |
| `quitProcess`   | `pid`, `name`       | page already asked "Quit X?"; send SIGTERM (NSRunningApplication.terminate() for apps) |
| `ready`         |                     | page loaded; push the latest snapshot right away                  |

Opened in a normal browser (no `webkit.messageHandlers`), each page loads `sample.js` and renders the sample snapshot,
so the design can be checked without the app.

## Snapshot

All bytes are raw byte counts (numbers). Memory is shown binary (GiB, labelled "GB", like Activity Monitor);
disk and network decimal (like Finder). Rates are per second. History arrays: oldest first, covering the last hour
(Swift keeps one point every 30 s = 120 points; fewer is fine right after launch). Any field may be `null` when
unknown; the page shows "–".

```js
{
  time: "2026-10-17T18:17:00-04:00",
  host: { model: "MacBook Pro", chip: "Apple M3 Pro", pCores: 5, eCores: 6, gpuCores: 14,
          memBytes: 19327352832, os: "macOS 26.0", uptimeSec: 706000 },

  memory: {
    totalBytes, usedBytes,              // used = app + wired + compressed (Activity Monitor "Memory Used")
    appBytes, wiredBytes, compressedBytes, cachedBytes, freeBytes,
    pressurePct,                        // 100 - kern.memorystatus_level (same as `memory_pressure` "free percentage")
    level: "normal" | "warn" | "critical",   // kern.memorystatus_vm_pressure_level 1/2/4
    swapUsedBytes, swapTotalBytes,      // sysctl vm.swapusage
    swapOutBytesSinceBoot,              // vm_statistics64 swapouts * page size
    history: { pressurePct: [..], swapUsedBytes: [..] }
  },

  cpu: {
    totalPct, userPct, systemPct, idlePct,
    cores: [ { kind: "P" | "E", pct } ],     // performance cores first
    load: [1min, 5min, 15min],
    history: [ totalPct... ]
  },

  gpu: { pct, history: [..] },               // IOAccelerator PerformanceStatistics "Device Utilization %"

  energy: {
    batteryPct, pluggedIn, charging, fullyCharged, adapterWatts,
    cycles, healthPct,                       // MaxCapacity / DesignCapacity
    minutesLeft,                             // on battery: IOPS time to empty; plugged in: estimate at current draw, or null
    thermal: "nominal" | "fair" | "serious" | "critical",   // ProcessInfo.thermalState
    fanRPM,                                  // null if unreadable (page then just omits the fan)
    impact                                   // sum of the top-level processes' energy right now
  },

  disk: {
    volume: "Macintosh HD", totalBytes, usedBytes, freeBytes,
    readBps, writeBps,                       // IOBlockStorageDriver Statistics deltas
    readTodayBytes, writtenTodayBytes,       // since local midnight (persist the midnight baseline; since boot if unknown)
    bigUsers: [ { name, bytes } ] | null     // background scan every 30 min; null while the first scan runs
  },

  network: {
    iface: "Wi-Fi", inBps, outBps, packetsInPs, packetsOutPs,
    inTodayBytes, outTodayBytes              // since local midnight, same baseline idea
  },

  live: {                                    // the strip charts: last 5 minutes, one point every 2 s
    stepSec: 2,                              // up to 150 points each, oldest first; starts with 1 point at launch
    pressurePct: [..], swapUsedBytes: [..],
    cpuUserPct: [..], cpuSystemPct: [..], gpuPct: [..],
    diskReadBps: [..], diskWriteBps: [..],
    netInBps: [..], netOutBps: [..],
    energyImpact: [..]                       // sum of the top-level processes' energy (same units as Proc.energy)
  },

  totals: { processes, threads },

  processes: [ Proc ]   // top level rows; Swift does the grouping
}

Proc = {
  id,                  // stable string: "pid:123" or "group:claude" / "group:claude-code"
  pid,                 // null for a synthetic group
  name,
  kind: "app" | "process" | "group" | "session",
  user,                // "vinnie", "root", "_windowserver"
  memBytes,            // phys_footprint (what Activity Monitor's Memory column shows); groups = sum
  cpuPct, cpuTimeSec, threads,
  energy,              // Activity Monitor-style energy impact (rough is fine; groups = sum)
  compressedBytes,     // Activity Monitor's "Compressed Memory" (TASK_VM_INFO.compressed); groups = sum. Can exceed
                       // memBytes for a virtual machine (guest memory). Null for root's and other users' processes
  idleWakeupsPs,       // Activity Monitor's "Idle Wake Ups", per second; groups = sum
  diskReadBps, diskWriteBps, netInBps, netOutBps,
  model,               // sessions only: "Opus" | "Sonnet" | "Haiku" | "Fable" | null
  note,                // optional short gray words from Swift (e.g. "virtual machine"); the page also has its own table
  children: [ Proc ]   // helpers under their app; Claude Code sessions under group:claude-code
}
```

Grouping wanted: an app's helper processes under the app (by responsible pid / bundle path). The Claude desktop app
gets its virtualization VM process as a child named "Sandbox virtual machine". Every `claude` CLI process becomes a
`session` child of one synthetic "Claude Code" group, named by its working folder's last path component, with
`model` from the newest `"model"` field in that folder's newest transcript under ~/.claude/projects (map
claude-opus-* → Opus, claude-sonnet-* → Sonnet, claude-haiku-* → Haiku, claude-fable-* → Fable).
