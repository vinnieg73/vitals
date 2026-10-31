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
    energy: { watts: 14.2, batteryPct: 100, pluggedIn: true, charging: false, fullyCharged: true, adapterWatts: 96, cycles: 47, healthPct: 100,
      minutesLeft: 380, thermal: "nominal", fanRPM: 0, impact: null },
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
      proc(330, "coreaudiod", "process", null, 22 * M, 0.3, 2210, 12, 0.2, 0, 0, 0, 0)
    ]
  };
  // energy impact right now = sum of the top-level processes' energy (DATA.md)
  snap.energy.impact = Math.round(snap.processes.reduce(function (t, p) { return t + (p.energy || 0); }, 0) * 10) / 10;

  /* live: the strip charts, 150 points at 2 s (the last 5 minutes), oldest first, ending on the numbers above */
  var N = 150;
  function bump(t, c, w) { var d = (t - c) / w; return Math.exp(-d * d); }
  function live(seed, f, last, round) {
    var r = rng(seed), a = [];
    for (var i = 0; i < N; i++) a.push(f(i / (N - 1), r));
    a[N - 1] = last;
    return round ? a.map(function (v) { return Math.round(v * round) / round; }) : a;
  }
  snap.live = {
    stepSec: 2,
    pressurePct: live(7, function (t, r) { return 63 + 15 * (1 - Math.exp(-t * 3.2)) / (1 - Math.exp(-3.2)) - 7 * bump(t, .5, .035) + (r() - .5) * 1.4; }, 78, 10),
    memUsedPct: live(29, function (t, r) { return 84 + 8 * (1 - Math.exp(-t * 3)) / (1 - Math.exp(-3)) - 4 * bump(t, .5, .035) + (r() - .5) * 1; }, Math.round(snap.memory.usedBytes / snap.memory.totalBytes * 1000) / 10, 10),
    swapUsedBytes: live(11, function (t, r) { return (5.94 + .08 * t + (r() - .5) * .01) * G; }, snap.memory.swapUsedBytes),
    cpuUserPct: live(4, function (t, r) { return 21 + Math.sin(t * 13) * 3 + (r() - .5) * 8 + 22 * bump(t, .7, .025) + 9 * bump(t, .22, .02); }, snap.cpu.userPct, 10),
    cpuSystemPct: live(3, function (t, r) { return 10.5 + (r() - .5) * 4 + 6 * bump(t, .7, .025) + 3 * bump(t, .22, .02); }, snap.cpu.systemPct, 10),
    gpuPct: live(5, function (t, r) { return 8 + (r() - .5) * 4 + 13 * bump(t, .71, .02) + 4 * bump(t, .4, .04); }, snap.gpu.pct, 10),
    diskReadBps: live(9, function (t, r) { var b = r() < .08 ? 25 + r() * 35 : 0; return (6 + r() * 9 + b + 30 * bump(t, .22, .015)) * 1e6; }, snap.disk.readBps),
    diskWriteBps: live(13, function (t, r) { var b = r() < .12 ? 30 + r() * 45 : 0; return (24 + r() * 16 + b + 20 * bump(t, .7, .02)) * 1e6; }, snap.disk.writeBps),
    netInBps: live(17, function (t, r) { var b = r() < .1 ? 2 + r() * 3.5 : 0; return (1.4 + r() * 1.6 + b + 3 * bump(t, .55, .03)) * 1e6; }, snap.network.inBps),
    netOutBps: live(19, function (t, r) { var b = r() < .06 ? .5 + r() * .8 : 0; return (.18 + r() * .25 + b) * 1e6; }, snap.network.outBps),
    energyImpact: live(23, function (t, r) { return 82 + (r() - .5) * 12 + 26 * bump(t, .7, .025) + 10 * bump(t, .22, .02); }, snap.energy.impact, 10),
    powerW: live(31, function (t, r) { return 11.5 + (r() - .5) * 2 + 9 * bump(t, .7, .025) + 3.5 * bump(t, .22, .02); }, snap.energy.watts, 10)
  };
  // like the real feed: the first point of a rate series has nothing to compare against
  ["diskReadBps", "diskWriteBps", "netInBps", "netOutBps"].forEach(function (k) { snap.live[k][0] = null; });
  var KEYS = Object.keys(snap.live).filter(function (k) { return k !== "stepSec"; });

  // ?fresh: right after launch, one point per series (?fresh=12 keeps 12)
  // ?gaps: energy impact and watts null while no page was showing (a long run of nulls), plus a short gap in CPU
  var q = location.search + location.hash;
  var fresh = /fresh(?:=(\d+))?/.exec(q);
  if (fresh) {
    var keep = Math.max(1, +(fresh[1] || 1));
    KEYS.forEach(function (k) { snap.live[k] = snap.live[k].slice(-keep); });
    if (keep === 1) ["diskReadBps", "diskWriteBps", "netInBps", "netOutBps"].forEach(function (k) { snap.live[k][0] = null; });
  }
  if (/gaps/.test(q)) {
    var E = snap.live.energyImpact;
    for (var i = 0; i < E.length - 18; i++) E[i] = null;
    for (i = E.length - 3; i < E.length; i++) E[i] = null;
    snap.energy.impact = null;
    var W = snap.live.powerW;
    for (i = 0; i < W.length - 18; i++) W[i] = null;
    for (i = W.length - 3; i < W.length; i++) W[i] = null;
    snap.energy.watts = null;
    var C = snap.live.cpuUserPct, Cs = snap.live.cpuSystemPct;
    for (i = 60; i < 75 && i < C.length; i++) { C[i] = null; Cs[i] = null; }
  }

  function push(k, v) { var a = snap.live[k]; if (a.length >= N) a.shift(); a.push(v); }
  window.VitalsSample = {
    snapshot: snap,
    start: function (update) {
      update(snap);
      var still = /still/.test(q);
      if (still || (window.matchMedia && matchMedia("(prefers-reduced-motion: reduce)").matches)) return;
      var r = rng(42);
      setInterval(function () { VitalsSample.tick(r); update(snap); }, 2000);
    },
    // one 2 s step: every live series shifts left by one and gets a new point
    tick: function (r) {
      r = r || Math.random;
      var m = snap.memory, c = snap.cpu, d = snap.disk, n = snap.network, e = snap.energy;
      m.pressurePct = Math.round(Math.max(72, Math.min(84, m.pressurePct + (r() - .5) * 1.6)) * 10) / 10;
      c.userPct = Math.round(Math.max(8, 22.4 + (r() - .5) * 9) * 10) / 10;
      c.systemPct = Math.round(Math.max(4, 11.1 + (r() - .5) * 4) * 10) / 10;
      c.totalPct = Math.round(c.userPct + c.systemPct); c.idlePct = Math.round((100 - c.userPct - c.systemPct) * 10) / 10;
      c.history.shift(); c.history.push(c.totalPct);
      c.cores.forEach(function (k) { k.pct = Math.max(2, Math.min(98, k.pct + (r() - .5) * 10)); });
      snap.gpu.pct = Math.round(Math.max(1, 9 + (r() - .5) * 4) * 10) / 10; snap.gpu.history.shift(); snap.gpu.history.push(snap.gpu.pct);
      d.readBps = (6 + r() * 9 + (r() < .08 ? 25 + r() * 35 : 0)) * 1e6;
      d.writeBps = (24 + r() * 16 + (r() < .12 ? 30 + r() * 45 : 0)) * 1e6;
      n.inBps = (1.4 + r() * 1.6 + (r() < .1 ? 2 + r() * 3.5 : 0)) * 1e6;
      n.outBps = (.18 + r() * .25 + (r() < .06 ? .5 + r() * .8 : 0)) * 1e6;
      if (e.impact != null || r() < .3) e.impact = Math.round((84 + (r() - .5) * 10) * 10) / 10;
      if (e.watts != null || r() < .3) e.watts = Math.round((12 + (r() - .5) * 2.4) * 10) / 10;
      m.usedBytes = Math.max(15.6, Math.min(17.2, m.usedBytes / G + (r() - .5) * .12)) * G;
      push("pressurePct", m.pressurePct); push("memUsedPct", Math.round(m.usedBytes / m.totalBytes * 1000) / 10); push("swapUsedBytes", m.swapUsedBytes);
      push("cpuUserPct", c.userPct); push("cpuSystemPct", c.systemPct); push("gpuPct", snap.gpu.pct);
      push("diskReadBps", d.readBps); push("diskWriteBps", d.writeBps); push("netInBps", n.inBps); push("netOutBps", n.outBps);
      push("energyImpact", e.impact); push("powerW", e.watts);
    }
  };
})();
