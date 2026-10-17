/* Sample snapshot for previewing the pages in a browser (the app never loads this file).
   Numbers are Vinnie's Mac on 17 Oct 2026, rounded. */
(function () {
  var G = 1073741824, M = 1048576;
  function rng(seed) { return function () { seed |= 0; seed = seed + 0x6D2B79F5 | 0; var t = Math.imul(seed ^ seed >>> 15, 1 | seed); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
  function series(n, seed, f) { var r = rng(seed), a = []; for (var i = 0; i < n; i++) a.push(f(i / (n - 1), r)); return a; }
  function sess(folder, model, mb, cpu, t) {
    return { id: "pid:" + folder, pid: 4000 + folder.length * 7, name: folder, kind: "session", user: "vinnie", model: model,
      memBytes: mb * M, cpuPct: cpu, cpuTimeSec: t, threads: 17, energy: cpu * 0.7,
      diskReadBps: 0, diskWriteBps: 1e5, netInBps: 28e3, netOutBps: 8e3 };
  }
  function proc(pid, name, kind, user, mem, cpu, t, thr, en, dr, dw, ni, no, kids) {
    return { id: (typeof pid === "string" ? "group:" : "pid:") + pid, pid: typeof pid === "string" ? 611 : pid, name: name, kind: kind, user: user, memBytes: mem, cpuPct: cpu, cpuTimeSec: t,
      threads: thr, energy: en, diskReadBps: dr, diskWriteBps: dw, netInBps: ni, netOutBps: no, children: kids || [] };
  }
  var sessions = [
    sess("claude-meter", "Sonnet", 340, 2.1, 6500), sess("nhl-gm-tool", "Opus", 310, 9.0, 18764),
    sess("claude-dashboard", "Fable", 290, 4.4, 9545), sess("travel-log", "Sonnet", 260, 1.2, 4231),
    sess("swarm-watch", "Sonnet", 240, 0.6, 3492), sess("Utilities", "Sonnet", 230, 0.9, 3107),
    sess("shift-hours", "Sonnet", 210, 0.2, 2649), sess("parlay-builder", "Sonnet", 180, 0.1, 2283)
  ];
  function sum(k) { return sessions.reduce(function (s, x) { return s + x[k]; }, 0); }
  var snap = {
    time: "2026-10-17T18:17:00-04:00",
    host: { model: "MacBook Pro", chip: "Apple M3 Pro", pCores: 5, eCores: 6, gpuCores: 14, memBytes: 18 * G, os: "macOS 26.0", uptimeSec: 8 * 86400 + 4 * 3600 },
    memory: {
      totalBytes: 18 * G, usedBytes: 16.62 * G, appBytes: 10.84 * G, wiredBytes: 2.71 * G, compressedBytes: 3.07 * G,
      cachedBytes: 1.21 * G, freeBytes: 0.17 * G, pressurePct: 78, level: "warn",
      swapUsedBytes: 6.02 * G, swapTotalBytes: 7 * G, swapOutBytesSinceBoot: 230 * G,
      history: {
        pressurePct: series(120, 7, function (t, r) { return 63 + 15 * Math.pow(t, 1.3) + (r() - .5) * 3.2; }),
        swapUsedBytes: series(120, 11, function (t, r) { return (5.05 + 0.97 * Math.min(1, Math.round(t * 7) / 6.2) + (r() - .5) * .04) * G; })
      }
    },
    cpu: {
      totalPct: 34, userPct: 22.4, systemPct: 11.1, idlePct: 66.5,
      cores: [58, 41, 37, 22, 19].map(function (v) { return { kind: "P", pct: v }; }).concat(
        [64, 55, 49, 48, 40, 33].map(function (v) { return { kind: "E", pct: v }; })),
      load: [5.2, 4.8, 4.6],
      history: series(120, 3, function (t, r) { return 31 + Math.sin(t * 9) * 5 + (r() - .5) * 12; })
    },
    gpu: { pct: 9, history: series(120, 5, function (t, r) { return 8 + (r() - .5) * 6 + (t > .7 && t < .75 ? 7 : 0); }) },
    energy: { batteryPct: 100, pluggedIn: true, charging: false, fullyCharged: true, adapterWatts: 96, cycles: 47, healthPct: 100,
      minutesLeft: 380, thermal: "nominal", fanRPM: 0 },
    disk: { volume: "Macintosh HD", totalBytes: 494.4e9, usedBytes: 400.1e9, freeBytes: 94.3e9, readBps: 14.2e6, writeBps: 38.6e6,
      readTodayBytes: 61.2e9, writtenTodayBytes: 97.4e9,
      bigUsers: [{ name: "Xcode simulators", bytes: 58e9 }, { name: "Photos library", bytes: 41e9 }, { name: "Downloads", bytes: 22e9 },
        { name: "Claude VM bundle", bytes: 18e9 }, { name: "NHL GM database", bytes: 1.5e9 }] },
    network: { iface: "Wi-Fi", inBps: 2.4e6, outBps: 310e3, packetsInPs: 1840, packetsOutPs: 920, inTodayBytes: 18.7e9, outTodayBytes: 3.2e9 },
    totals: { processes: 712, threads: 4812 },
    processes: [
      { id: "group:claude", pid: 812, name: "Claude", kind: "app", user: "vinnie", memBytes: 11.5 * G, cpuPct: 43.1, cpuTimeSec: 220279,
        threads: 182, energy: 40.1, diskReadBps: 3.1e6, diskWriteBps: 6.2e6, netInBps: 1.12e6, netOutBps: 120e3, children: [
          proc(990, "Sandbox virtual machine", "process", "vinnie", 10.1 * G, 41.0, 211212, 38, 38.2, 2.8e6, 5.9e6, 1.1e6, 96e3),
          Object.assign(proc(812, "Claude", "app", "vinnie", 0.62 * G, 1.2, 6067, 64, 1.1, 0.2e6, 0.2e6, 10e3, 14e3), { note: "the app itself" }),
          proc(813, "Claude Helper (Renderer)", "process", "vinnie", 0.51 * G, 0.6, 2000, 40, 0.5, 0.1e6, 0.1e6, 5e3, 6e3),
          proc(814, "Claude Helper (GPU)", "process", "vinnie", 0.27 * G, 0.3, 1000, 40, 0.3, 0, 0, 5e3, 4e3)] },
      { id: "group:claude-code", pid: null, name: "Claude Code", kind: "group", user: "vinnie", memBytes: sum("memBytes"), cpuPct: 18.5,
        cpuTimeSec: sum("cpuTimeSec"), threads: 136, energy: 11.8, diskReadBps: 0.4e6, diskWriteBps: 0.9e6, netInBps: 220e3, netOutBps: 64e3, children: sessions },
      proc(0, "kernel_task", "process", "root", 1.9 * G, 8.0, 148702, 612, 5.2, 6.1e6, 24.8e6, 0, 0),
      proc("safari", "Safari", "app", "vinnie", 1.62 * G, 12.0, 35050, 96, 14.0, 1.2e6, 0.8e6, 900e3, 60e3, [
        proc(1201, "Safari Web Content", "process", "vinnie", 0.74 * G, 6.2, 12001, 21, 6.1, 0.2e6, 0.1e6, 400e3, 20e3),
        proc(1202, "Safari Web Content", "process", "vinnie", 0.41 * G, 3.0, 9001, 19, 3.2, 0.1e6, 0.1e6, 300e3, 10e3),
        Object.assign(proc(611, "Safari", "app", "vinnie", 0.47 * G, 2.8, 14048, 56, 4.7, 0.9e6, 0.6e6, 200e3, 30e3), { note: "the app itself" })]),
      proc(402, "WindowServer", "process", "_windowserver", 612 * M, 18.0, 79533, 24, 9.1, 0.1e6, 0.2e6, 0, 0),
      proc(530, "mds_stores", "process", "root", 240 * M, 6.0, 11565, 9, 3.4, 2.4e6, 1.9e6, 0, 0),
      proc(733, "Messages", "app", "vinnie", 210 * M, 0.3, 2462, 18, 0.2, 0, 0, 4e3, 2e3),
      proc(640, "Finder", "app", "vinnie", 180 * M, 0.2, 3493, 11, 0.1, 0.1e6, 0, 0, 0),
      proc(1500, "Swarm Watch", "app", "vinnie", 148 * M, 0.8, 4844, 14, 0.6, 0, 0, 12e3, 3e3),
      proc(1501, "Vitals", "app", "vinnie", 74 * M, 0.9, 120, 9, 0.4, 0, 0, 0, 0),
      proc(1502, "Claude Meter", "app", "vinnie", 62 * M, 0.4, 3130, 9, 0.3, 0, 0, 6e3, 1e3),
      proc(1503, "Wakey", "app", "vinnie", 18 * M, 0.0, 192, 4, 0.0, 0, 0, 0, 0),
      proc(1, "launchd", "process", "root", 34 * M, 0.1, 6010, 5, 0.1, 0, 0, 0, 0),
      proc(320, "bluetoothd", "process", "root", 12 * M, 0.1, 812, 7, 0.0, 0, 0, 0, 0),
      proc(330, "coreaudiod", "process", "_coreaudiod", 22 * M, 0.3, 2210, 12, 0.2, 0, 0, 0, 0)
    ]
  };
  window.VitalsSample = {
    snapshot: snap,
    start: function (update) {
      update(snap);
      var still = /still/.test(location.search + location.hash);
      if (still || (window.matchMedia && matchMedia("(prefers-reduced-motion: reduce)").matches)) return;
      var r = rng(42);
      setInterval(function () {
        var c = Math.round(34 + (r() - .5) * 6);
        snap.cpu.totalPct = c; snap.cpu.history.shift(); snap.cpu.history.push(c);
        snap.cpu.cores.forEach(function (k) { k.pct = Math.max(2, Math.min(98, k.pct + (r() - .5) * 10)); });
        snap.gpu.pct = Math.max(1, 9 + (r() - .5) * 4); snap.gpu.history.shift(); snap.gpu.history.push(snap.gpu.pct);
        snap.network.inBps = (2.4 + (r() - .5) * .6) * 1e6;
        snap.disk.writeBps = (38.6 + (r() - .5) * 8) * 1e6;
        update(snap);
      }, 2000);
    }
  };
})();
