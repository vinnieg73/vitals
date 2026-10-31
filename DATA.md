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
    swapOutBytesSinceBoot               // vm_statistics64 swapouts * page size
  },

  cpu: {
    totalPct, userPct, systemPct, idlePct,
    cores: [ { kind: "P" | "E", pct } ],     // performance cores first
    load: [1min, 5min, 15min]
  },

  gpu: { pct,                 // IOAccelerator PerformanceStatistics "Device Utilization %"
         rendererPct, tilerPct, // "Renderer Utilization %" (pixels, shading) and "Tiler Utilization %" (shapes, geometry)
         memBytes },            // "In use system memory": the GPU's share of the Mac's RAM in use now

  energy: {
    batteryPct, pluggedIn, charging, fullyCharged, adapterWatts,
    cycles, healthPct,                       // MaxCapacity / DesignCapacity
    minutesLeft,                             // on battery: IOPS time to empty; plugged in: estimate at current draw, or null
    thermal: "nominal" | "fair" | "serious" | "critical",   // ProcessInfo.thermalState
    fanRPM,                                  // null if unreadable (page then just omits the fan)
    impact,                                  // sum of the top-level processes' energy right now (unitless score; 100 ≈ one core busy)
    watts                                    // the whole Mac's draw in W, one decimal: AppleSmartBattery PowerTelemetryData
                                             // SystemLoad (mW), read every tick (one property). Null with no battery
  },

  disk: {
    volume: "Macintosh HD", totalBytes, usedBytes, freeBytes,
    readBps, writeBps,                       // IOBlockStorageDriver Statistics deltas
    readTodayBytes, writtenTodayBytes        // since local midnight (persist the midnight baseline; since boot if unknown)
  },

  network: {
    iface: "Wi-Fi", inBps, outBps, packetsInPs, packetsOutPs,
    inTodayBytes, outTodayBytes              // since local midnight, same baseline idea
  },

  live: {                                    // the strip charts: last 5 minutes, one point every 2 s
    stepSec: 2,                              // up to 150 points each, oldest first; starts with 1 point at launch
                                             // a null point in every series = a gap (Mac asleep, or resting while the screens sleep);
                                             // a gap is one null per 2 s away (at most 150), so index = time
    pressurePct: [..], swapUsedBytes: [..],
    memUsedPct: [..],                        // memory.usedBytes / totalBytes × 100, one decimal (Activity Monitor's Memory Used)
    cpuUserPct: [..], cpuSystemPct: [..], gpuPct: [..],
    diskReadBps: [..], diskWriteBps: [..],
    netInBps: [..], netOutBps: [..],
    energyImpact: [..],                      // sum of the top-level processes' energy (same units as Proc.energy)
    powerW: [..]                             // energy.watts. The Energy charts show this when it has numbers, else energyImpact
  },

  long: {                                    // only while the window shows: its 1-hour / 12-hour charts (LongHistory.swift)
    stepSec: 60,                             // one point a minute, up to 720 (12 h), oldest first; the last is the minute in progress
                                             // each point = the average of that minute's non-null samples of that series;
                                             // null = no sample that minute (the Mac asleep). Same keys as live.
                                             // Filled every tick, window or not; in memory only, starts over with Vitals.
    pressurePct: [..], memUsedPct: [..], swapUsedBytes: [..], cpuUserPct: [..], cpuSystemPct: [..], gpuPct: [..],
    diskReadBps: [..], diskWriteBps: [..], netInBps: [..], netOutBps: [..], energyImpact: [..], powerW: [..]
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
  idleWakeupsPs,       // Activity Monitor's "Idle Wake Ups", per second; groups = sum
  diskReadBps, diskWriteBps, netInBps, netOutBps,
  model,               // sessions only: "Opus" | "Sonnet" | "Haiku" | "Fable" | null
  note,                // optional short gray words from Swift (e.g. "virtual machine", "runs on node"); the page also has its own table
  startedBy,           // top-level loose processes only: "Claude Code · <session folder>" or the app that started it (parent
                       // chain, 12 hops), else null. A node / python3 / ruby / bun / deno row is named after its script.
  children: [ Proc ]   // helpers under their app; Claude Code sessions under group:claude-code
}
```

Grouping wanted: an app's helper processes under the app (by responsible pid / bundle path). The Claude desktop app
gets its virtualization VM process as a child named "Sandbox virtual machine". Every `claude` CLI process becomes a
`session` child of one synthetic "Claude Code" group, named by its working folder's last path component, with
`model` from the newest `"model"` field in that folder's newest transcript under ~/.claude/projects (map
claude-opus-* → Opus, claude-sonnet-* → Sonnet, claude-haiku-* → Haiku, claude-fable-* → Fable).
