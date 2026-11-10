#!/usr/bin/env node
/* Page checks in headless Chromium with fake snapshots (no app, no window on screen):
     node scripts/test-pages.js
   Needs Playwright (local or global npm install) and its Chromium. Prints PASS / FAIL per check; exit 1 on any FAIL. */
"use strict";
const path = require("path");

function loadPlaywright() {
  try { return require("playwright"); } catch (e) { /* fall back to a global install */ }
  const root = require("child_process").execSync("npm root -g").toString().trim();
  return require(path.join(root, "playwright"));
}

const RES = path.resolve(__dirname, "..", "Resources");
const url = (page) => "file://" + path.join(RES, page) + "?still";
let failures = 0;
function check(name, ok, detail) {
  if (!ok) failures++;
  console.log((ok ? "PASS" : "FAIL") + "  " + name + (ok ? "" : "  (" + detail + ")"));
}

// A snapshot like the sampler sends: `real` points, then `gap` empty slots for a stretch away (the last of them
// is the waking sample's own point), with no disk / network rates on the waking sample.
function gapSnapshot(base, real, gap) {
  const s = JSON.parse(JSON.stringify(base));
  const keys = Object.keys(s.live).filter((k) => k !== "stepSec");
  keys.forEach((k) => {
    const pts = [];
    for (let i = 0; i < real; i++) pts.push(k === "diskReadBps" ? 77.7e6 : k === "netInBps" ? 6.6e6 : k === "memUsedPct" ? 55 : base.live[k][base.live[k].length - 1]);
    for (let i = 0; i < gap; i++) pts.push(null);
    s.live[k] = pts.slice(-150);
  });
  s.disk.readBps = null; s.disk.writeBps = null;
  s.network.inBps = null; s.network.outBps = null;
  s.energy.impact = null; s.energy.watts = null;
  return s;
}

(async () => {
  const { chromium } = loadPlaywright();
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 880 } });
    const errors = [];
    page.on("pageerror", (e) => errors.push(String(e)));

    /* ---------- app.js: Vitals.now ---------- */
    await page.goto(url("window.html"));
    await page.waitForFunction(() => window.Vitals && window.Vitals.last);
    const nowCases = await page.evaluate(() => {
      const V = window.Vitals;
      return { cur: V.now(3, [1, 2]), last: V.now(null, [1, 2]), pastGap: V.now(null, [5, null]), empty: V.now(null, []), none: V.now(null, null) };
    });
    check("now: the current value wins", nowCases.cur === 3, JSON.stringify(nowCases));
    check("now: falls back to the newest point", nowCases.last === 2, JSON.stringify(nowCases));
    check("now: never reaches back past a gap", nowCases.pastGap === null, JSON.stringify(nowCases));
    check("now: empty or missing series give null", nowCases.empty === null && nowCases.none === null, JSON.stringify(nowCases));

    /* ---------- window: right after a 60 s stretch away (30 empty slots) ---------- */
    const base = await page.evaluate(() => window.VitalsSample.snapshot);
    const s60 = gapSnapshot(base, 100, 30);
    await page.evaluate((s) => window.Vitals.update(s), s60);
    const ro = await page.evaluate(() => ({
      disk: document.querySelector("#ch-disk .ro .two").textContent,
      net: document.querySelector("#ch-net .ro .two").textContent,
      energy: document.querySelector("#ch-energy .ro .big").textContent,
    }));
    check("window: disk speed after a gap isn't the one from before it", !/77\.7/.test(ro.disk) && /–/.test(ro.disk), ro.disk);
    check("window: network speed after a gap isn't the one from before it", !/6\.6/.test(ro.net) && /–/.test(ro.net), ro.net);
    check("window: energy after a gap isn't the one from before it", /–/.test(ro.energy), ro.energy);

    // hover the last point before the stretch: 30 slots of 2 s back from "now" = one minute ago
    async function hoverSlot(slot) {
      return page.evaluate((slot) => {
        const plot = document.querySelector("#ch-mem .plot"), r = plot.getBoundingClientRect();
        const x = r.left + slot / (window.Vitals.CAP - 1) * plot.clientWidth;
        document.getElementById("scope").dispatchEvent(new MouseEvent("mousemove", { clientX: x, clientY: r.top + 5, bubbles: true }));
        const tag = document.querySelector("#ch-mem .htag");
        return { time: document.getElementById("htime").textContent, tag: tag.style.display === "none" ? null : tag.textContent };
      }, slot);
    }
    const lastReal = await hoverSlot(149 - 30);
    check("hover: the last point before a 60 s gap says −1:00", lastReal.time === "−1:00", JSON.stringify(lastReal));
    check("hover: and shows that point's value", lastReal.tag === "55%", JSON.stringify(lastReal));
    const inGap = await hoverSlot(149 - 10);
    check("hover: inside the gap there's no value", inGap.tag === "–" && inGap.time === "−0:20", JSON.stringify(inGap));
    const nowSlot = await hoverSlot(149);
    check("hover: the right edge is now", nowSlot.time === "now", JSON.stringify(nowSlot));
    await page.evaluate(() => document.getElementById("scope").dispatchEvent(new MouseEvent("mouseleave")));

    // the line ends where the real points end, not at the right edge
    const geo = await page.evaluate(() => {
      const plot = document.querySelector("#ch-mem .plot"), dot = plot.querySelector("circle.nd-a");
      return { cx: +dot.getAttribute("cx"), w: plot.clientWidth };
    });
    const want = (149 - 30) / 149 * geo.w;
    check("chart: the trace ends a minute back, not at now", Math.abs(geo.cx - want) < 1.5, JSON.stringify(geo) + " want cx " + want.toFixed(1));

    /* ---------- window: after a night asleep (a full chart of empty slots) ---------- */
    const night = gapSnapshot(base, 100, 150);
    await page.evaluate((s) => window.Vitals.update(s), night);
    const empty = await page.evaluate(() => {
      const plot = document.querySelector("#ch-mem .plot");
      return { line: plot.querySelector("path.ln").getAttribute("d"), dot: plot.querySelector("circle.nd-a").style.display,
        disk: document.querySelector("#ch-disk .ro .two").textContent };
    });
    check("chart: after a long sleep nothing from before it is drawn", empty.line === "" && empty.dot === "none", JSON.stringify(empty));
    check("window: and the speeds read –", !/77\.7/.test(empty.disk), empty.disk);

    // the next tick brings numbers back
    const next = JSON.parse(JSON.stringify(night));
    Object.keys(next.live).filter((k) => k !== "stepSec").forEach((k) => { next.live[k].shift(); next.live[k].push(k === "diskReadBps" ? 1.5e6 : 50); });
    next.disk.readBps = 1.5e6; next.disk.writeBps = 2e6;
    await page.evaluate((s) => window.Vitals.update(s), next);
    const back = await page.evaluate(() => document.querySelector("#ch-disk .ro .two").textContent);
    check("window: speeds come back on the next tick", /1\.5/.test(back), back);

    /* ---------- popover: same gap ---------- */
    await page.goto(url("popover.html"));
    await page.waitForFunction(() => window.Vitals && window.Vitals.last);
    await page.evaluate((s) => window.Vitals.update(s), s60);
    const pop = await page.evaluate(() => ({ disk: document.getElementById("r-disk").textContent, net: document.getElementById("r-net").textContent }));
    check("popover: speeds after a gap aren't the ones from before it", !/77\.7/.test(pop.disk) && !/6\.6/.test(pop.net), JSON.stringify(pop));

    /* ---------- amber / red come from the app's verdict (s.strain, memStrain), never worked out on the page ---------- */
    // Held: pressure fell to 67 (under the 70 line) but the menu bar icon is still amber, so the pages are too.
    function strained(base, pressure, word, code) {
      const s = JSON.parse(JSON.stringify(base));
      s.memory.pressurePct = pressure; s.memory.level = "normal"; s.memory.swapUsedBytes = 1e9;
      s.strain.memory = word; s.strain.swap = "ok";
      s.live.pressurePct = s.live.pressurePct.map(() => pressure);
      s.live.swapUsedBytes = s.live.swapUsedBytes.map(() => 1e9);
      s.live.memStrain = s.live.memStrain.map(() => code);
      return s;
    }
    const memLook = () => page.evaluate(() => {
      const win = document.querySelector("#ch-mem .ro .big"), pop = document.querySelector("#r-mem b");
      const plot = document.querySelector("#ch-mem .plot") || document.querySelector(".pch .plot");
      const swapDd = Array.from(document.querySelectorAll("#ch-mem .kv dt")).filter((d) => d.textContent === "Swap").map((d) => d.nextElementSibling.className)[0];
      const swapSpan = Array.from(document.querySelectorAll("#r-mem span")).filter((d) => /^Swap/.test(d.textContent)).map((d) => d.className)[0];
      return { big: (win || pop).className.trim(), dot: plot.querySelector("circle.nd-a").getAttribute("class"),
        stops: Array.from(plot.querySelectorAll("stop")).map((x) => x.getAttribute("class")), swap: (swapDd == null ? swapSpan : swapDd) || "" };
    });
    for (const p of ["window.html", "popover.html"]) {
      const name = p.replace(".html", "");
      await page.goto(url(p));
      await page.waitForFunction(() => window.Vitals && window.Vitals.last);
      await page.evaluate((s) => window.Vitals.update(s), strained(base, 67, "warn", 1));
      const held = await memLook();
      check(name + ": memory stays amber while the icon holds it (pressure 67)", /\bw\b/.test(held.big) && /warn/.test(held.dot) && held.stops.every((c) => c === "st-warn"), JSON.stringify(held));
      await page.evaluate((s) => window.Vitals.update(s), strained(base, 72, "ok", 0));
      const calm = await memLook();
      check(name + ": no color of its own when the app says ok (pressure 72)", calm.big === (name === "window" ? "big" : "") && !/warn|crit/.test(calm.dot) && calm.stops.every((c) => c === "st-ok"), JSON.stringify(calm));
      const sw = strained(base, 40, "warn", 1); sw.strain.swap = "warn";
      await page.evaluate((s) => window.Vitals.update(s), sw);
      const swapWarn = await memLook();
      const swCrit = strained(base, 90, "crit", 2); swCrit.strain.swap = "crit";
      await page.evaluate((s) => window.Vitals.update(s), swCrit);
      const swapCrit = await memLook();
      check(name + ": the swap number takes the app's color", /\bw\b/.test(swapWarn.swap) && /\bc\b/.test(swapCrit.swap) && calm.swap.trim() === "" && /\bc\b/.test(swapCrit.big), JSON.stringify([calm.swap, swapWarn.swap, swapCrit.swap]));
    }
    // The 12-hour chart is colored by the stored levels: pressure hovering at 70 with one held stretch is one amber
    // run, not stripes.
    await page.goto(url("window.html"));
    await page.waitForFunction(() => window.Vitals && window.Vitals.last);
    const hover12 = strained(base, 69, "warn", 1);
    hover12.long.pressurePct = hover12.long.pressurePct.map((v, i) => (v == null ? null : i % 2 ? 71 : 69));
    hover12.long.swapUsedBytes = hover12.long.swapUsedBytes.map((v) => (v == null ? null : 1e9));
    hover12.long.memStrain = hover12.long.memStrain.map((v, i) => (v == null ? null : i >= 600 ? 1 : 0));
    await page.evaluate((s) => { window.Vitals.update(s); window.Vitals.setRange("12h"); }, hover12);
    const long12 = await page.evaluate(() => {
      const plot = document.querySelector("#ch-mem .plot"), r = plot.getBoundingClientRect();
      const stops = Array.from(plot.querySelectorAll("stop")).map((x) => x.getAttribute("class"));
      const tagAt = (slot) => {
        document.getElementById("scope").dispatchEvent(new MouseEvent("mousemove", { clientX: r.left + slot / 719 * plot.clientWidth, clientY: r.top + 5, bubbles: true }));
        return plot.querySelector(".htag").className;
      };
      const out = { runs: stops.filter((c, i) => i === 0 || c !== stops[i - 1]), early: tagAt(100), late: tagAt(700) };
      document.getElementById("scope").dispatchEvent(new MouseEvent("mouseleave"));
      window.Vitals.setRange("5m");
      return out;
    });
    check("window: the 12-hour chart is colored by the stored levels (one amber run, no stripes)", long12.runs.join(",") === "st-ok,st-warn", JSON.stringify(long12.runs));
    check("window: hovering a stored point shows its stored level", !/\bw\b/.test(long12.early) && /\bw\b/.test(long12.late), JSON.stringify([long12.early, long12.late]));

    /* ---------- Quit is only offered for the current user's processes ---------- */
    await page.goto(url("window.html"));
    await page.waitForFunction(() => window.Vitals && window.Vitals.last);
    const owners = JSON.parse(JSON.stringify(base));
    const rowOf = (id, pid, name, user, mem) => ({ id, pid, name, kind: "process", user, memBytes: mem, cpuPct: 1, cpuTimeSec: 10, threads: 3, energy: 1,
      diskReadBps: 0, diskWriteBps: 0, netInBps: 0, netOutBps: 0, started: "123", children: [] });
    owners.host.user = "vinnie";
    owners.processes = [rowOf("pid:7001", 7001, "mine", "vinnie", 9e9), rowOf("pid:7002", 7002, "roots", "root", 8e9),
      rowOf("pid:7003", 7003, "windowservers", "_windowserver", 7e9), rowOf("pid:7004", 7004, "someone-elses", "bob", 6e9),
      rowOf("pid:7005", 7005, "nobodys", null, 5e9), rowOf("pid:1", 1, "launchd", "vinnie", 4e9)];
    await page.evaluate((s) => window.Vitals.update(s), owners);
    const quit = {};
    for (const id of ["pid:7001", "pid:7002", "pid:7003", "pid:7004", "pid:7005", "pid:1"]) {
      await page.click('tr[data-id="' + id + '"]');
      quit[id] = await page.evaluate(() => { const b = document.getElementById("quitBtn"); return { off: b.disabled, text: b.textContent, user: document.querySelector("tr.sel td:last-child").textContent }; });
    }
    check("quit: offered for the current user's own process", quit["pid:7001"].off === false && /Quit mine/.test(quit["pid:7001"].text), JSON.stringify(quit["pid:7001"]));
    check("quit: never for root's, _windowserver's, another user's, an unknown user's, or pid 1",
      ["pid:7002", "pid:7003", "pid:7004", "pid:7005", "pid:1"].every((id) => quit[id].off === true && quit[id].text === "Quit"), JSON.stringify(quit));
    check("window: the User column names system users", quit["pid:7002"].user === "root" && quit["pid:7003"].user === "_windowserver" && quit["pid:7005"].user === "–", JSON.stringify(quit));
    // without the current user's name in the feed, nothing can be quit
    delete owners.host.user;
    await page.evaluate((s) => window.Vitals.update(s), owners);
    await page.click('tr[data-id="pid:7002"]');
    await page.click('tr[data-id="pid:7001"]');
    const noName = await page.evaluate(() => document.getElementById("quitBtn").disabled);
    check("quit: nothing is offered when the feed doesn't say who the user is", noName === true, String(noName));

    /* ---------- a Claude Code session whose model isn't known: still counted, a neutral gray dot ---------- */
    const unknown = JSON.parse(JSON.stringify(base));
    const code = unknown.processes.find((p) => p.id === "group:claude-code");
    code.children[0].model = null;
    const readDots = () => page.evaluate(() => {
      const probe = document.createElement("i");
      probe.style.background = "var(--ink-4)";
      document.body.appendChild(probe);
      const gray = getComputedStyle(probe).backgroundColor;
      probe.remove();
      const dots = Array.from(document.querySelectorAll(".dots .mdot"));
      return { n: dots.length, gray: dots.filter((d) => getComputedStyle(d).backgroundColor === gray).length,
        plain: dots.filter((d) => d.className.trim() === "mdot m-").length };
    });
    for (const p of ["window.html", "popover.html"]) {
      await page.goto(url(p));
      await page.waitForFunction(() => window.Vitals && window.Vitals.last);
      await page.evaluate((s) => window.Vitals.update(s), unknown);
      const d = await readDots();
      const name = p.replace(".html", "");
      check(name + ": a session with no known model is still counted", d.n === code.children.length, JSON.stringify({ n: d.n }));
      check(name + ": ...and its dot is neutral gray, the others keep their color", d.gray === 1 && d.plain === 1, JSON.stringify({ n: d.n, gray: d.gray, plain: d.plain }));
    }

    /* ---------- every page still loads cleanly with the sample feed ---------- */
    for (const p of ["window.html", "popover.html", "help.html"]) {
      await page.goto(url(p));
      await page.waitForTimeout(150);
    }
    check("pages: no script errors", errors.length === 0, errors.join(" | "));
  } finally {
    await browser.close();
  }
  console.log(failures === 0 ? "test-pages: all passed" : "test-pages: " + failures + " failed");
  process.exit(failures === 0 ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
