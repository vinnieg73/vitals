// Instrument dials: wider Vitals menu bar icons built from today's needle gauge.
window.WIDE_FACTORY = function (h) {
  "use strict";
  var FONT = "-apple-system,Inter,system-ui,sans-serif";
  var D = Math.PI / 180;
  var NAME = { cpu: "CPU", gpu: "GPU", ram: "RAM" };

  function f(n) { return (+n).toFixed(2); }
  function clamp(p) { return Math.max(0, Math.min(100, p)); }
  function txt(x, y, s, size, weight, color, anchor) {
    return '<text x="' + f(x) + '" y="' + f(y) + '" text-anchor="' + (anchor || "middle") + '" font-family="' + FONT + '" font-size="' + size +
      '" font-weight="' + weight + '" fill="' + color + '" style="font-variant-numeric:tabular-nums">' + s + "</text>";
  }
  function line(x1, y1, x2, y2, c, w, cap) {
    return '<line x1="' + f(x1) + '" y1="' + f(y1) + '" x2="' + f(x2) + '" y2="' + f(y2) + '" stroke="' + c + '" stroke-width="' + w + '" stroke-linecap="' + (cap || "round") + '"/>';
  }
  function arc(cx, cy, r, a0, a1, c, w) {
    return '<path d="' + h.arcPath(cx, cy, r, a0 * D, a1 * D) + '" fill="none" stroke="' + c + '" stroke-width="' + w + '" stroke-linecap="round"/>';
  }
  // Today's gauge, scaled: a solid arc from 195 to -15 degrees, a needle that stops short of it, a round hub.
  // o: {sw, from, to, inset, hub, ticks}
  function dial(cx, cy, r, pct, c, o) {
    o = o || {};
    var sw = o.sw || 1.7, a0 = o.from == null ? 195 : o.from, a1 = o.to == null ? -15 : o.to;
    var inset = o.inset == null ? 2.2 : o.inset, hub = o.hub || 1.6;
    var a = (a0 - (a0 - a1) * clamp(pct) / 100) * D;
    var s = arc(cx, cy, r, a0, a1, c, sw);
    if (o.ticks) for (var i = 1; i < o.ticks; i++) {
      var t = (a0 - (a0 - a1) * i / o.ticks) * D, r0 = r - sw / 2 - 0.2, r1 = r0 - (o.tickLen || 1.6);
      s += line(cx + r0 * Math.cos(t), cy - r0 * Math.sin(t), cx + r1 * Math.cos(t), cy - r1 * Math.sin(t), h.css("--bar-ink-2"), o.tickW || 0.9, "butt");
    }
    s += line(cx, cy, cx + (r - inset) * Math.cos(a), cy - (r - inset) * Math.sin(a), c, o.nw || sw);
    s += '<circle cx="' + f(cx) + '" cy="' + f(cy) + '" r="' + hub + '" fill="' + c + '"/>';
    return s;
  }
  function c(k) { return h.col(h.sev(k)); }
  function labC(k) { return h.sev(k) ? c(k) : h.css("--bar-ink-2"); }

  return [
    { id: "dl-1", name: "Three dials", w: 58, rec: true,
      desc: "Today's gauge, three times over, like the dials on a car dashboard: CPU, GPU and RAM side by side, each with its own needle.",
      how: ["Left to right: CPU, GPU, RAM; each needle points at how busy that part is",
            "Strained: that dial and its label turn amber, or red when critical",
            "58 pt, 24 pt wider than today"],
      draw: function () {
        return h.K.map(function (k, i) {
          var cx = 9 + i * 20;
          return dial(cx, 10.9, 6.9, h.V[k], c(k), { from: 190, to: -10, inset: 2.1 }) + txt(cx, 19.6, NAME[k], 7, 600, labC(k));
        }).join("");
      } },

    { id: "dl-2", name: "Big RAM dial, two small", w: 58,
      desc: "A big RAM dial in the middle, like today's icon, with smaller CPU and GPU dials on either side, the way a car puts the speedometer between smaller gauges.",
      how: ["Middle: RAM, the same reading as today's icon; left CPU, right GPU",
            "Strained: that dial and its label turn amber, or red when critical",
            "58 pt, 24 pt wider than today"],
      draw: function () {
        var s = "", side = [["cpu", 8.5], ["gpu", 49.5]];
        side.forEach(function (p) { s += dial(p[1], 12.4, 5.3, h.V[p[0]], c(p[0]), { sw: 1.5, from: 180, to: 0, inset: 1.6, hub: 1.3 }) + txt(p[1], 19.6, NAME[p[0]], 7, 600, labC(p[0])); });
        s += dial(29, 12.4, 8.5, h.V.ram, c("ram"), { sw: 1.9, from: 180, to: 0, inset: 2.3, hub: 1.9 });
        s += txt(29, 19.6, "RAM", 7, 600, labC("ram"));
        return s;
      } },

    { id: "dl-3", name: "One wide dial, two tick readouts", w: 64,
      desc: "One large dial whose needle always shows the busiest part, with two small rows of ticks beside it for the other two parts.",
      how: ["The dial's letter says which part the needle shows; each row of ticks shows another part's level",
            "Strained: the needle jumps to that part and turns amber, or red when critical",
            "64 pt, 30 pt wider than today"],
      draw: function () {
        var top = h.worst() || h.busiest(), rest = h.K.filter(function (k) { return k !== top; });
        var cx = 15, cy = 17, r = 13;
        var s = dial(cx, cy, r, h.V[top], c(top), { sw: 1.9, from: 180, to: 0, inset: 2.6, hub: 2, ticks: 4, tickLen: 1.8 });
        s += txt(7, 16.4, NAME[top].charAt(0), 7, 700, c(top));
        rest.forEach(function (k, j) {
          var y0 = j === 0 ? 4 : 13, x0 = 33, n = 8, col = c(k), lit = Math.round(clamp(h.V[k]) / 100 * n);
          s += txt(x0, y0 + 5, NAME[k].charAt(0), 7, 700, labC(k), "start");
          for (var i = 0; i < n; i++) {
            var x = x0 + 7 + i * 3;
            s += '<rect x="' + x + '" y="' + y0 + '" width="2" height="5" rx=".4" fill="' + (i < lit ? col : h.css("--track")) + '"/>';
          }
        });
        return s;
      } }
  ];
};
