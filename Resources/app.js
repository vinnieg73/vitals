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
      if (bps >= 999.95e6) return (bps / 1e9).toFixed(1) + " GB/s";   // never "1000.0 MB/s"
      if (bps >= 1e6) return (bps / 1e6).toFixed(1) + " MB/s";
      if (bps >= 1e3) return Math.round(bps / 1e3) + " KB/s";
      return Math.round(bps) + " B/s";
    },
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
  function friendly(p) {
    if (!p) return "";
    if (p.name === "Sandbox virtual machine" || /Virtualization/.test(p.name)) return "Claude's sandbox";
    if (p.id === "group:claude-code") return "Claude Code";
    return p.name;
  }

  // What is strained (amber) or critical (red) is decided once, by the app, with the menu bar icon's own rules
  // (StatusIcon.Judge: each line is lower on the way out than on the way in, so nothing flickers), and sent as
  // s.strain and, per chart point, live.memStrain / long.memStrain. The pages only draw it, so the icon and the
  // pages can't disagree. (Swap is judged by size, not by how full it looks: macOS adds 1 GB swap files as it
  // needs them, so used / total sits near 100% even when nothing is wrong.)
  var STRAIN = ["ok", "warn", "crit"];
  function strainOf(s, k) { var v = (s.strain || {})[k]; return v === "warn" || v === "crit" ? v : "ok"; }
  function memState(s) { return strainOf(s, "memory"); }
  // "w" / "c" / "" for the swap number
  function swapCls(s) { var v = strainOf(s, "swap"); return v === "crit" ? "c" : v === "warn" ? "w" : ""; }
  // memory strain per chart point, for coloring the used-% line (null where there's no point)
  function memSev(s, L) {
    var S = L.memStrain || [], n = (L.memUsedPct || []).length, out = [];
    for (var i = 0; i < n; i++) {
      var v = S[S.length - n + i];
      out.push(isNum(v) ? STRAIN[Math.max(0, Math.min(2, Math.round(v)))] : null);
    }
    return out;
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
        var it = { id: p.id, rowId: p.id, name: p.name, desc: note(p), by: p.startedBy || null, proc: p, sessions: p.id === "group:claude-code" ? (p.children || []) : null };
        SUM.forEach(function (k) { it[k] = p[k]; });
        out.push(it);
      }
    });
    return out;
  }

  /* ---------- live strip charts (last 5 min, one point every 2 s) ---------- */
  // Points sit at fixed slots counted from the right edge ("now"), so right after launch a single point
  // is drawn at the right edge and the rest of the axis stays empty. null points are gaps, never zeros.
  var CAP = 150, SVGNS = "http://www.w3.org/2000/svg", uid = 0;
  F.rateParts = function (bps) {
    if (!isNum(bps)) return ["–", ""];
    if (bps <= 0) return ["0", "KB/s"];
    if (bps >= 999.95e6) return [(bps / 1e9).toFixed(1), "GB/s"];
    if (bps >= 1e6) return [(bps / 1e6).toFixed(1), "MB/s"];
    if (bps >= 1e3) return [String(Math.round(bps / 1e3)), "KB/s"];
    return [String(Math.round(bps)), "B/s"];
  };
  function niceMax(v, floor) {
    v = Math.max(isNum(v) ? v : 0, floor || 0);
    if (!(v > 0)) return 1;
    var steps = [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10], e = Math.pow(10, Math.floor(Math.log10(v)));
    for (var i = 0; i < steps.length; i++) if (steps[i] * e >= v * 0.9999) return steps[i] * e;
    return 10 * e;
  }
  function maxOf(a) { var m = 0; for (var i = 0; i < a.length; i++) if (isNum(a[i]) && a[i] > m) m = a[i]; return m; }
  function mk(tag, cls, parent) {
    var e = document.createElementNS(SVGNS, tag);
    if (cls) e.setAttribute("class", cls);
    parent.appendChild(e);
    return e;
  }
  function tail(a, cap) { a = a || []; cap = cap || CAP; return a.length > cap ? a.slice(-cap) : a; }
  function linePath(X, Y) {
    var d = "", pen = false;
    for (var i = 0; i < X.length; i++) {
      if (Y[i] == null) { pen = false; continue; }
      d += (pen ? "L" : "M") + X[i].toFixed(1) + "," + Y[i].toFixed(1); pen = true;
    }
    return d;
  }
  function areaPath(X, Ytop, Ybot) {   // one closed shape per unbroken run of points
    var d = "", i = 0, n = X.length;
    while (i < n) {
      if (Ytop[i] == null) { i++; continue; }
      var s = i; while (i < n && Ytop[i] != null) i++;
      if (i - s < 2) continue;
      for (var k = s; k < i; k++) d += (k === s ? "M" : "L") + X[k].toFixed(1) + "," + Ytop[k].toFixed(1);
      for (k = i - 1; k >= s; k--) d += "L" + X[k].toFixed(1) + "," + Ybot[k].toFixed(1);
      d += "Z";
    }
    return d;
  }

  // opt: { type: "level" | "stack" | "single" | "mirror", max, floor, thr, crit, pad, padTop, mini }
  // A strip holds CAP points (5 minutes at 2 s) with gridlines at fifths, unless setRange says otherwise.
  //  level:  a = a %, colored per point gray / amber / red, from sev[] when given, else by value (>= thr, >= crit)
  //  stack:  a = system % (bottom), b = user % (on top)
  //  single: a
  //  mirror: a above the midline (read, in), b below (write, out), one shared scale
  function Strip(host, opt) {
    this.opt = opt; this.w = 0; this.h = 0; this.a = []; this.b = []; this.max = 1; this.cap = CAP; this.divs = 5;
    var s = this.svg = mk("svg", "strip", host), t = opt.type;
    s.setAttribute("aria-hidden", "true");
    this.grid = [];
    for (var m = 1; m < 5; m++) this.grid.push(mk("line", "gl", s));
    if (t === "level") {
      this.gid = "vg" + (++uid);
      this.grad = mk("linearGradient", null, mk("defs", null, s));
      this.grad.setAttribute("id", this.gid);
      this.grad.setAttribute("gradientUnits", "userSpaceOnUse");
      this.stops = [];
    }
    this.fa = mk("path", "f-" + t + "-a", s);
    this.fb = t === "stack" || t === "mirror" ? mk("path", "f-" + t + "-b", s) : null;
    this.ref = mk("line", t === "level" ? "thr" : t === "mirror" ? "mid" : "gl", s);
    this.la = mk("path", "ln ln-" + t + "-a", s);
    this.lb = t === "mirror" ? mk("path", "ln ln-" + t + "-b", s) : null;
    this.base = t === "mirror" ? null : mk("line", "base", s);
    this.da = mk("circle", "nd nd-a", s);
    this.db = t === "mirror" ? mk("circle", "nd nd-b", s) : null;
    [this.da, this.db].forEach(function (c) { if (c) c.setAttribute("r", opt.mini ? "2.4" : "2.6"); });
    if (t === "level") { this.fa.style.fill = "url(#" + this.gid + ")"; this.la.style.stroke = "url(#" + this.gid + ")"; }
    if (opt.mini && t !== "level" && t !== "mirror") this.ref.style.display = "none";
  }
  Strip.prototype.size = function (w, h) {
    w = Math.max(1, Math.round(w)); h = Math.max(1, Math.round(h));
    if (w === this.w && h === this.h) return false;
    this.w = w; this.h = h;
    var s = this.svg;
    s.setAttribute("width", w); s.setAttribute("height", h); s.setAttribute("viewBox", "0 0 " + w + " " + h);
    var divs = this.divs;
    this.grid.forEach(function (g, k) {
      var x = (w * (k + 1) / divs).toFixed(1);
      g.setAttribute("x1", x); g.setAttribute("x2", x); g.setAttribute("y1", 0); g.setAttribute("y2", h);
    });
    if (this.grad) { this.grad.setAttribute("x1", 0); this.grad.setAttribute("x2", w); this.grad.setAttribute("y1", 0); this.grad.setAttribute("y2", 0); }
    return true;
  };
  // how many points fit across (`cap`) and how many gridline gaps (`divs`): the window's 1-hour and 12-hour views
  Strip.prototype.setRange = function (cap, divs) {
    if (cap === this.cap && divs === this.divs) return;
    this.cap = cap; this.divs = divs;
    while (this.grid.length < divs - 1) { var g = mk("line", "gl", this.svg); this.svg.insertBefore(g, this.grid[0] || null); this.grid.push(g); }
    while (this.grid.length > divs - 1) this.svg.removeChild(this.grid.pop());
    var w = this.w, h = this.h; this.w = 0; this.size(w, h);
  };
  // index (into the drawn arrays) under x pixels from the left, or -1 where there is no data yet
  Strip.prototype.index = function (x) {
    var n = Math.max(this.a.length, this.b.length), cap = this.cap;
    var slot = Math.round(Math.max(0, Math.min(1, x / this.w)) * (cap - 1));
    var i = slot - (cap - n);
    return i >= 0 && i < n ? i : -1;
  };
  Strip.prototype.xOf = function (i, n) { return (this.cap - n + i) / (this.cap - 1) * this.w; };
  // nowState: "", "warn" or "crit" for the end dot of a level chart; sev: per-point states for a level chart
  Strip.prototype.draw = function (a, b, nowState, sev) {
    var o = this.opt, t = o.type;
    a = this.a = tail(a, this.cap); b = this.b = tail(b, this.cap);
    if (!this.w) return;
    var w = this.w, h = this.h, pad = o.pad == null ? 7 : o.pad, top = o.padTop || pad, bot = h - pad;
    var n = Math.max(a.length, b.length), X = [], i;
    for (i = 0; i < n; i++) X.push(this.xOf(i, n));
    var self = this, max, Ya, Yb, Ybase;
    function setLine(el, x1, y1, x2, y2) { el.setAttribute("x1", x1); el.setAttribute("y1", y1); el.setAttribute("x2", x2); el.setAttribute("y2", y2); }
    function clamp(v, m) { return Math.max(0, Math.min(v, m)); }
    if (t === "mirror") {
      max = niceMax(Math.max(maxOf(a), maxOf(b)) * 1.04, o.floor);
      var mid = (top + bot) / 2, half = mid - top;
      Ya = a.map(function (v) { return isNum(v) ? mid - clamp(v, max) / max * half : null; });
      Yb = b.map(function (v) { return isNum(v) ? mid + clamp(v, max) / max * half : null; });
      Ybase = X.map(function () { return mid; });
      this.fa.setAttribute("d", areaPath(X, Ya, Ybase));
      this.fb.setAttribute("d", areaPath(X, Yb, Ybase));
      this.la.setAttribute("d", linePath(X, Ya));
      this.lb.setAttribute("d", linePath(X, Yb));
      setLine(this.ref, 0, mid, w, mid);
      this.top = top; this.bot = bot;
    } else {
      if (o.max) max = o.max;
      else max = niceMax((t === "stack" ? maxOf(a.map(function (v, k) { return isNum(v) && isNum(b[k]) ? v + b[k] : v; })) : maxOf(a)) * 1.08, o.floor);
      var sy = function (v) { return isNum(v) ? bot - clamp(v, max) / max * (bot - top) : null; };
      Ybase = X.map(function () { return bot; });
      if (t === "stack") {
        Ya = a.map(sy);
        var Yt = a.map(function (v, k) { return isNum(v) && isNum(b[k]) ? sy(v + b[k]) : null; });
        this.fa.setAttribute("d", areaPath(X, Ya, Ybase));
        this.fb.setAttribute("d", areaPath(X, Yt.map(function (y, k) { return Ya[k] == null ? null : y; }), Ya));
        this.la.setAttribute("d", linePath(X, Yt));
        Ya = Yt;
      } else {
        Ya = a.map(sy);
        this.fa.setAttribute("d", areaPath(X, Ya, Ybase));
        this.la.setAttribute("d", linePath(X, Ya));
      }
      var ry = t === "level" ? (o.thr ? sy(o.thr) : 0) : sy(max / 2);
      if (t === "level" && !o.thr) this.ref.style.display = "none";
      setLine(this.ref, 0, ry.toFixed(1), w, ry.toFixed(1));
      this.ref.classList.toggle("on", t === "level" && !!nowState);
      setLine(this.base, 0, bot, w, bot);
      this.top = top; this.bot = bot;
    }
    if (t === "level") this.colorStops(a, X, w, o, sev ? tail(sev, this.cap) : null);
    this.max = max;
    // "now" dots: where each trace ends (its last real point)
    function dot(c, Y, state) {
      if (!c) return;
      var k = Y.length - 1; while (k >= 0 && Y[k] == null) k--;
      if (k < 0) { c.style.display = "none"; return; }
      c.style.display = "";
      c.setAttribute("cx", X[k].toFixed(1)); c.setAttribute("cy", Y[k].toFixed(1));
      c.classList.toggle("warn", state === "warn"); c.classList.toggle("crit", state === "crit");
    }
    dot(this.da, Ya, t === "level" ? nowState : "");
    dot(this.db, Yb || [], "");
    return self;
  };
  Strip.prototype.colorStops = function (a, X, w, o, sev) {
    var want = [], prev = null;
    function state(v, i) { return !isNum(v) ? null : sev ? sev[sev.length - a.length + i] || "ok" : v >= (o.crit || 101) ? "crit" : v >= o.thr ? "warn" : "ok"; }
    for (var i = 0; i < a.length; i++) {
      var c = state(a[i], i); if (!c) continue;
      if (c !== prev) {
        var off = Math.max(0, Math.min(1, (X[i] - (i ? (X[i] - X[i - 1]) / 2 : 0)) / w));
        if (prev) want.push([off, prev]);
        want.push([off, c]); prev = c;
      }
    }
    if (!prev) prev = "ok";
    want.push([1, prev]);
    var g = this.grad;
    while (this.stops.length < want.length) this.stops.push(mk("stop", null, g));
    while (this.stops.length > want.length) g.removeChild(this.stops.pop());
    this.stops.forEach(function (s, k) {
      s.setAttribute("offset", want[k][0].toFixed(4));
      s.setAttribute("class", "st-" + want[k][1]);
    });
  };
  // the live block, or one point made from the current numbers when the feed has none
  function liveOf(s) {
    var L = s.live;
    var m = s.memory || {}, used = m.totalBytes && isNum(m.usedBytes) ? m.usedBytes / m.totalBytes * 100 : null;
    if (L && L.pressurePct) {
      // feeds from before memUsedPct existed: one point made from the current numbers, aligned to the end
      if (!L.memUsedPct) { L.memUsedPct = L.pressurePct.map(function () { return null; }); L.memUsedPct[L.memUsedPct.length - 1] = used; }
      return L;
    }
    var c = s.cpu || {}, d = s.disk || {}, n = s.network || {}, e = s.energy || {};
    return { stepSec: 2, pressurePct: [m.pressurePct], memUsedPct: [used], memStrain: [STRAIN.indexOf(memState(s))], swapUsedBytes: [m.swapUsedBytes], cpuUserPct: [c.userPct], cpuSystemPct: [c.systemPct],
      gpuPct: [(s.gpu || {}).pct], diskReadBps: [d.readBps], diskWriteBps: [d.writeBps], netInBps: [n.inBps], netOutBps: [n.outBps], energyImpact: [e.impact], powerW: [e.watts] };
  }
  // The Energy charts show real watts (the whole Mac's draw) when the feed has them: Macs with a battery. Macs
  // without one, and feeds from before watts existed, show the energy impact score instead.
  function useWatts(s, L) {
    return isNum((s.energy || {}).watts) || ((L || {}).powerW || []).some(isNum);
  }
  // current value, or the newest point of its live series when the current one is null. Never a point from
  // before a gap: after a sleep that would show a speed from before it as if it were now.
  function now(v, series) {
    if (isNum(v)) return v;
    var a = series || [];
    return a.length && isNum(a[a.length - 1]) ? a[a.length - 1] : null;
  }

  /* ---------- wiring ---------- */
  var Vitals = window.Vitals = {
    F: F, note: note, flat: flat, items: items, friendly: friendly, memState: memState, memSev: memSev, swapCls: swapCls,
    post: post, native: native,
    Strip: Strip, niceMax: niceMax, liveOf: liveOf, useWatts: useWatts, now: now, CAP: CAP,
    GiB: GiB, isNum: isNum,
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
