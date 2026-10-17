/* Vitals: shared page code. Swift calls Vitals.update(snapshot) every 2 s (see DATA.md).
   Opened in a browser without the app, the page renders sample.js instead. */
(function () {
  "use strict";
  var GiB = 1073741824, MiB = 1048576;
  var listeners = [], last = null;
  var native = !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vitals);

  function post(action, extra) {
    var msg = Object.assign({ action: action }, extra || {});
    if (native) window.webkit.messageHandlers.vitals.postMessage(msg);
    else console.log("[vitals] " + JSON.stringify(msg));
  }

  /* ---------- formatting ---------- */
  function isNum(v) { return typeof v === "number" && isFinite(v); }
  var F = {
    dash: "–",
    // memory: binary, labelled GB/MB like Activity Monitor
    mem: function (b) {
      if (!isNum(b)) return "–";
      return b >= GiB ? (b / GiB).toFixed(2) + " GB" : Math.round(b / MiB) + " MB";
    },
    gb: function (b, d) { return isNum(b) ? (b / GiB).toFixed(d == null ? 2 : d) : "–"; },
    gbShort: function (b) {   // "10 GB", "1.4 GB", "612 MB"
      if (!isNum(b)) return "–";
      if (b >= 10 * GiB) return Math.round(b / GiB) + " GB";
      if (b >= 0.95 * GiB) return (b / GiB).toFixed(1).replace(/\.0$/, "") + " GB";
      return Math.round(b / MiB) + " MB";
    },
    // disk / network: decimal like Finder
    dgb: function (b, d) { return isNum(b) ? (b / 1e9).toFixed(d == null ? 1 : d) + " GB" : "–"; },
    bytes: function (b) {
      if (!isNum(b)) return "–";
      if (b >= 1e12) return (b / 1e12).toFixed(2) + " TB";
      if (b >= 1e9) return (b / 1e9).toFixed(b >= 1e11 ? 0 : 1) + " GB";
      if (b >= 1e6) return (b / 1e6).toFixed(0) + " MB";
      return Math.round(b / 1e3) + " KB";
    },
    rate: function (bps) {
      if (!isNum(bps)) return "–";
      if (bps <= 0) return "–";
      if (bps >= 1e9) return (bps / 1e9).toFixed(1) + " GB/s";
      if (bps >= 1e6) return (bps / 1e6).toFixed(1) + " MB/s";
      if (bps >= 1e3) return Math.round(bps / 1e3) + " KB/s";
      return Math.round(bps) + " B/s";
    },
    rateZero: function (bps) { return isNum(bps) && bps > 0 ? F.rate(bps) : "0 KB/s"; },
    pct: function (v, d) { return isNum(v) ? v.toFixed(d || 0) : "–"; },
    int: function (v) { return isNum(v) ? Math.round(v).toLocaleString("en-US") : "–"; },
    dur: function (sec) {
      if (!isNum(sec)) return "–";
      sec = Math.max(0, Math.floor(sec));
      var h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60;
      return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
    },
    hm: function (min) {
      if (!isNum(min)) return "–";
      var h = Math.floor(min / 60), m = Math.round(min % 60);
      return h ? h + " h " + m + " m" : m + " min";
    },
    uptime: function (sec) {
      if (!isNum(sec)) return "–";
      var d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600);
      if (d) return d + (d === 1 ? " day " : " days ") + h + (h === 1 ? " hour" : " hours");
      var m = Math.floor(sec % 3600 / 60);
      return h + (h === 1 ? " hour " : " hours ") + m + " min";
    },
    esc: function (s) {
      return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
        return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
      });
    }
  };

  /* ---------- plain words for cryptic process names ---------- */
  var NOTES = {
    "kernel_task": "macOS itself, also writes swap",
    "WindowServer": "draws everything on screen",
    "launchd": "starts everything else",
    "mds": "Spotlight search", "mds_stores": "Spotlight search index", "mdworker": "Spotlight indexing", "mdworker_shared": "Spotlight indexing",
    "Safari": "web browser", "Google Chrome": "web browser", "Arc": "web browser", "Firefox": "web browser",
    "com.apple.WebKit.WebContent": "a web page", "Safari Web Content": "a web page",
    "com.apple.WebKit.Networking": "web downloads", "com.apple.WebKit.GPU": "web graphics",
    "coreaudiod": "sound", "bluetoothd": "Bluetooth", "backupd": "Time Machine backup",
    "photoanalysisd": "Photos face and scene scan", "mediaanalysisd": "photo and video analysis",
    "cloudd": "iCloud sync", "bird": "iCloud Drive", "fileproviderd": "iCloud Drive files",
    "softwareupdated": "software updates", "trustd": "certificate checks", "syspolicyd": "app security checks",
    "Finder": "files and folders", "Dock": "Dock and Launchpad", "SystemUIServer": "menu bar items",
    "ControlCenter": "Control Center", "loginwindow": "your login session", "Spotlight": "Spotlight search",
    "Messages": "", "Mail": "", "Music": "", "Photos": "",
    "Swarm Watch": "one of your tools", "Claude Meter": "one of your tools", "Wakey": "keeps your Mac awake",
    "Claude Dashboard": "one of your tools", "Vitals": "this app",
    "com.apple.Virtualization.VirtualMachine": "virtual machine",
    "Sandbox virtual machine": "runs Claude's tools safely",
    "Xcode": "", "Simulator": "iPhone simulator",
    "node": "JavaScript runtime", "python3": "Python", "Python": "Python"
  };
  function note(p) {
    if (p.kind === "group" && p.id === "group:claude-code") {
      var n = (p.children || []).length;
      return n + (n === 1 ? " session" : " sessions");
    }
    if (p.id === "group:claude" || (p.name === "Claude" && p.children && p.children.length)) return "desktop app and its sandbox";
    if (p.kind === "session") return p.model || "";
    if (p.note && !(p.children && p.children.length)) return p.note;
    if (NOTES[p.name] != null) return NOTES[p.name];
    return p.note || "";
  }

  /* ---------- reading the snapshot ---------- */
  function flat(list, out) {
    out = out || [];
    (list || []).forEach(function (p) { out.push(p); if (p.children) flat(p.children, out); });
    return out;
  }
  // biggest single memory user, looking inside groups (so "Claude's sandbox" beats "Claude")
  function biggest(s) {
    var best = null;
    (s.processes || []).forEach(function (p) {
      var cand = p;
      if (p.kind !== "group" && p.children && p.children.length) {
        var kid = p.children.slice().sort(function (a, b) { return (b.memBytes || 0) - (a.memBytes || 0); })[0];
        if (kid && kid.memBytes > p.memBytes * 0.6) cand = kid;
      }
      if (!best || (cand.memBytes || 0) > (best.memBytes || 0)) best = cand;
    });
    return best;
  }
  // the top-level row that frees the most if quit (an app with its helpers)
  function topApp(s) {
    var list = (s.processes || []).filter(function (p) {
      return p.id !== "group:claude-code" && p.pid != null && (p.kind === "app" || /^group:/.test(p.id));
    });
    list.sort(function (a, b) { return (b.memBytes || 0) - (a.memBytes || 0); });
    return list[0] || null;
  }
  function friendly(p) {
    if (!p) return "";
    if (p.name === "Sandbox virtual machine" || /Virtualization/.test(p.name)) return "Claude's sandbox";
    if (p.id === "group:claude-code") return "Claude Code";
    return p.name;
  }

  function memState(s) {
    var m = s.memory || {};
    var swapFrac = m.swapTotalBytes ? m.swapUsedBytes / m.swapTotalBytes : 0;
    if (m.level === "critical" || (swapFrac >= 0.97 && m.pressurePct >= 85)) return "crit";
    if (m.level === "warn" || m.pressurePct >= 70 || swapFrac >= 0.75) return "warn";
    return "ok";
  }
  function cpuState(s) { var c = s.cpu || {}; return c.totalPct >= 90 ? "busy" : c.totalPct >= 60 ? "working" : "calm"; }
  function hot(s) { var t = (s.energy || {}).thermal; return t === "serious" || t === "critical"; }
  function batteryLow(s) { var e = s.energy || {}; return !e.pluggedIn && isNum(e.batteryPct) && e.batteryPct <= 15; }
  function diskLow(s) { var d = s.disk || {}; return d.totalBytes && d.freeBytes / d.totalBytes < 0.07; }

  // the sentence at the top of the window and popover
  function summary(s) {
    var m = s.memory || {}, ms = memState(s);
    var swapFrac = m.swapTotalBytes ? m.swapUsedBytes / m.swapTotalBytes : 0;
    var big = biggest(s), totalGB = F.gbShort(m.totalBytes || (s.host || {}).memBytes);
    var others = [];
    if (hot(s)) others.push("hot");
    if (cpuState(s) === "busy") others.push("busy");
    if (batteryLow(s)) others.push("battery");
    if (diskLow(s)) others.push("disk");
    var rest = others.length ? "" : " Everything else is calm.";

    if (ms === "crit") return {
      sev: "crit", head: "Your Mac is out of memory.",
      sub: "Apps may freeze. " + friendly(big) + " is using <b>" + F.gbShort(big && big.memBytes) + " of your " + totalGB + "</b>, and swap is full.",
      short: friendly(big) + " is using " + F.gbShort(big && big.memBytes) + " of your " + totalGB + "."
    };
    if (ms === "warn") return {
      sev: "warn", head: "Your Mac is short on memory.",
      sub: friendly(big) + " is using <b>" + F.gbShort(big && big.memBytes) + " of your " + totalGB + "</b>" +
        (swapFrac >= 0.75 ? ", and swap is nearly full." : ".") + rest,
      short: friendly(big) + " is using " + F.gbShort(big && big.memBytes) + " of your " + totalGB + "."
    };
    if (hot(s)) return { sev: "warn", head: "Your Mac is running hot.", sub: "macOS is slowing things down to cool off. Busiest right now: <b>" + F.esc(busiest(s)) + "</b>.", short: "Busiest: " + busiest(s) + "." };
    if (cpuState(s) === "busy") return { sev: "ok", head: "Your Mac is busy.", sub: "The CPU is at <b>" + F.pct(s.cpu.totalPct) + "%</b>. Busiest right now: <b>" + F.esc(busiest(s)) + "</b>.", short: "Busiest: " + busiest(s) + "." };
    if (batteryLow(s)) return { sev: "warn", head: "Your battery is low.", sub: "<b>" + F.pct(s.energy.batteryPct) + "%</b> left, about " + F.hm(s.energy.minutesLeft) + ".", short: F.pct(s.energy.batteryPct) + "% left." };
    if (diskLow(s)) return { sev: "warn", head: "Your disk is almost full.", sub: "Only <b>" + F.dgb(s.disk.freeBytes) + "</b> free.", short: "Only " + F.dgb(s.disk.freeBytes) + " free." };
    return { sev: "ok", head: "Your Mac is doing fine.", sub: "Memory has room, the CPU is " + cpuState(s) + ", and nothing needs you.", short: "Nothing needs you." };
  }
  function busiest(s) {
    var p = flat(s.processes).filter(function (x) { return x.kind !== "group"; })
      .sort(function (a, b) { return (b.cpuPct || 0) - (a.cpuPct || 0); })[0];
    return p ? friendly(p) : "nothing";
  }
  function fix(s) {
    var ms = memState(s);
    if (ms === "ok") return null;
    var app = topApp(s);
    if (!app) return null;
    var name = app.name;
    return { name: name, pid: app.pid, bytes: app.memBytes,
      html: "Quit " + F.esc(name) + " while you're not using it. That frees about <b>" + F.gbShort(app.memBytes) + "</b>." };
  }

  // one entry per app, except Claude, which splits into its sandbox VM and the rest of the app
  var SUM = ["memBytes", "cpuPct", "energy", "diskReadBps", "diskWriteBps", "netInBps", "netOutBps"];
  function items(s) {
    var out = [];
    (s.processes || []).forEach(function (p) {
      var vm = p.id === "group:claude" && (p.children || []).filter(function (k) { return /sandbox|virtual/i.test(k.name); })[0];
      if (vm) {
        var rest = { id: p.id, rowId: p.id, name: "Claude app", desc: "the desktop app itself", proc: p };
        SUM.forEach(function (k) { rest[k] = Math.max(0, (p[k] || 0) - (vm[k] || 0)); });
        var v = { id: vm.id, rowId: vm.id, name: "Claude's sandbox", desc: "virtual machine inside the Claude app", proc: vm, short: "Claude VM" };
        SUM.forEach(function (k) { v[k] = vm[k]; });
        out.push(v, rest);
      } else {
        var it = { id: p.id, rowId: p.id, name: p.name, desc: note(p), proc: p, sessions: p.id === "group:claude-code" ? (p.children || []) : null };
        SUM.forEach(function (k) { it[k] = p[k]; });
        out.push(it);
      }
    });
    return out;
  }

  /* ---------- tiny charts ---------- */
  function spark(svg, vals, min, max, opts) {
    if (!svg) return;
    opts = opts || {};
    var W = 200, H = +(svg.getAttribute("data-h") || 40);
    svg.setAttribute("viewBox", "0 0 " + W + " " + H);
    svg.setAttribute("preserveAspectRatio", "none");
    vals = (vals || []).filter(isNum);
    if (vals.length < 2) { svg.innerHTML = ""; return; }
    var n = vals.length;
    var pts = vals.map(function (v, i) {
      var y = H - (Math.max(min, Math.min(max, v)) - min) / (max - min) * (H - 2) - 1;
      return [(i / (n - 1) * W).toFixed(1), y.toFixed(1)];
    });
    var line = pts.map(function (p, i) { return (i ? "L" : "M") + p[0] + " " + p[1]; }).join(" ");
    var ref = "";
    if (isNum(opts.ref)) {
      var ry = (H - (opts.ref - min) / (max - min) * (H - 2) - 1).toFixed(1);
      ref = '<line x1="0" x2="' + W + '" y1="' + ry + '" y2="' + ry + '" stroke="currentColor" stroke-opacity=".4" stroke-dasharray="2 3" vector-effect="non-scaling-stroke"/>';
    }
    svg.innerHTML = ref +
      '<path d="' + line + " L" + W + " " + H + " L0 " + H + ' Z" fill="currentColor" fill-opacity=".14"/>' +
      '<path d="' + line + '" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" vector-effect="non-scaling-stroke"/>';
  }
  function trend(vals) {
    vals = (vals || []).filter(isNum);
    if (vals.length < 6) return "";
    var k = Math.max(3, Math.floor(vals.length / 6));
    var a = avg(vals.slice(0, k)), b = avg(vals.slice(-k));
    if (b - a > Math.max(2, a * 0.05)) return "rising";
    if (a - b > Math.max(2, a * 0.05)) return "falling";
    return "steady";
  }
  function avg(a) { return a.reduce(function (x, y) { return x + y; }, 0) / a.length; }

  /* ---------- squarified treemap ---------- */
  // items: [{value,...}] sorted desc; returns items with x,y,w,h in a W x H box
  function treemap(items, W, H) {
    var out = [], total = items.reduce(function (s, it) { return s + it.value; }, 0);
    if (!total) return out;
    var scale = W * H / total;
    var rest = items.map(function (it) { return { it: it, a: it.value * scale }; });
    var x = 0, y = 0, w = W, h = H;
    while (rest.length) {
      var side = Math.min(w, h), row = [], best = Infinity;
      while (rest.length) {
        var test = row.concat([rest[0]]);
        var worst = worstRatio(test, side);
        if (worst > best) break;
        best = worst; row = test; rest.shift();
      }
      var sum = row.reduce(function (s, r) { return s + r.a; }, 0);
      var thick = sum / side, off = 0;
      row.forEach(function (r) {
        var len = r.a / thick;
        if (w >= h) out.push(Object.assign({}, r.it, { x: x, y: y + off, w: thick, h: len }));
        else out.push(Object.assign({}, r.it, { x: x + off, y: y, w: len, h: thick }));
        off += len;
      });
      if (w >= h) { x += thick; w -= thick; } else { y += thick; h -= thick; }
    }
    return out;
  }
  function worstRatio(row, side) {
    var sum = row.reduce(function (s, r) { return s + r.a; }, 0), mx = 0, mn = Infinity;
    row.forEach(function (r) { mx = Math.max(mx, r.a); mn = Math.min(mn, r.a); });
    var s2 = side * side, sum2 = sum * sum;
    return Math.max(s2 * mx / sum2, sum2 / (s2 * mn));
  }

  /* ---------- wiring ---------- */
  var Vitals = window.Vitals = {
    F: F, note: note, flat: flat, items: items, biggest: biggest, friendly: friendly, memState: memState, cpuState: cpuState,
    summary: summary, fix: fix, spark: spark, trend: trend, treemap: treemap, post: post, native: native,
    GiB: GiB, MiB: MiB, isNum: isNum,
    get last() { return last; },
    onUpdate: function (fn) { listeners.push(fn); if (last) fn(last); },
    update: function (s) {
      if (typeof s === "string") s = JSON.parse(s);
      last = s;
      listeners.forEach(function (fn) { try { fn(s); } catch (e) { console.error(e); } });
    },
    scrollTo: function (id) { var el = document.getElementById(id); if (el) el.scrollIntoView({ block: "start" }); },
    setTheme: function (t) { if (t === "light" || t === "dark") document.documentElement.setAttribute("data-theme", t); else document.documentElement.removeAttribute("data-theme"); }
  };

  // links like <a data-post="openHelp" data-section="tight">
  document.addEventListener("click", function (e) {
    var a = e.target.closest("[data-post]");
    if (!a) return;
    e.preventDefault();
    post(a.getAttribute("data-post"), a.dataset.section ? { section: a.dataset.section } : null);
  });

  function boot() {
    var m = /theme=(light|dark)/.exec(location.search + location.hash);
    if (m) Vitals.setTheme(m[1]);
    if (native) { post("ready"); return; }
    var sc = document.createElement("script");
    sc.src = "sample.js";
    sc.onload = function () { if (window.VitalsSample) window.VitalsSample.start(Vitals.update); };
    document.head.appendChild(sc);
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot); else boot();
})();
