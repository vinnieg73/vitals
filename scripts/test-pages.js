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
  s.energy.impact = null;
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
