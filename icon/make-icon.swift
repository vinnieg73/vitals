// Draws the Vitals app icon: a gray gauge whose needle sits in an amber arc, on a rounded square.
// Run from the vitals folder:  swift icon/make-icon.swift [--force]
// Writes only the files that are missing; --force redraws all of them (after changing this script).
// Writes, all at 1024 px:
//   icon/icon-1024.png, icon/icon-1024-dark.png        the whole icon, light and Dark mode ("Graphite")
//   icon/Vitals.icon/Assets/gauge-{light,dark}.png      the gauge alone on clear, for the Icon Composer file
//                                                       (macOS draws the tile from icon/Vitals.icon/icon.json)
import AppKit

let S: CGFloat = 1024

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

struct Palette {
    let top, bottom: NSColor        // tile gradient
    let rim: NSColor
    let track, tick, needle, hub, amber: NSColor
}
// Warm off-white, like the app's light theme.
let light = Palette(top: rgb(0xFBFAF7), bottom: rgb(0xE4E1DA), rim: rgb(0x000000, 0.08),
                    track: rgb(0xB9B6AE), tick: rgb(0x8E8B84), needle: rgb(0x4A4844), hub: rgb(0x4A4844), amber: rgb(0xE09A1D))
// "Graphite": the Vitals window's Dark mode grays, light needle, its brighter dark-mode amber.
let dark = Palette(top: rgb(0x323235), bottom: rgb(0x222224), rim: rgb(0xFFFFFF, 0.10),
                   track: rgb(0x4A4A4F), tick: rgb(0x808087), needle: rgb(0xE6E6EA), hub: rgb(0xE6E6EA), amber: rgb(0xEEA929))

/// tile: the whole icon on the macOS grid (824 body, inset 100). Without it, only the gauge, scaled up to the
/// full 1024 canvas the way Icon Composer layers are drawn (macOS adds the tile, mask and shadow).
let force = CommandLine.arguments.contains("--force")

func draw(_ p: Palette, tile: Bool, to path: String) {
    // A redraw differs by a little anti-aliasing noise, so the committed icon-1024.png is left alone unless asked.
    if !force && FileManager.default.fileExists(atPath: path) { return }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: S, height: S)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    if tile {
        let body = NSRect(x: 100, y: 100, width: 824, height: 824)
        let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

        // Soft drop shadow under the body.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = rgb(0x000000, 0.28)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        p.bottom.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGradient(starting: p.top, ending: p.bottom)!.draw(in: shape, angle: -90)
        p.rim.setStroke()
        let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 184.5, yRadius: 184.5)
        rim.lineWidth = 3
        rim.stroke()
    } else {
        // Same gauge, same place on the tile: scale the 824 body up to 1024 around the middle.
        let t = NSAffineTransform()
        t.translateX(by: 512, yBy: 512)
        t.scale(by: S / 824)
        t.translateX(by: -512, yBy: -512)
        t.concat()
    }

    let c = NSPoint(x: 512, y: 430)
    let r: CGFloat = 270
    let start: CGFloat = 200, end: CGFloat = -20   // degrees, sweeping clockwise over the top
    func angle(_ t: CGFloat) -> CGFloat { start - (start - end) * t }   // t: 0…1 along the dial

    func arc(_ t0: CGFloat, _ t1: CGFloat, color: NSColor, width: CGFloat) {
        let a = NSBezierPath()
        a.appendArc(withCenter: c, radius: r, startAngle: angle(t0), endAngle: angle(t1), clockwise: true)
        a.lineWidth = width
        a.lineCapStyle = .round
        color.setStroke()
        a.stroke()
    }

    // Gray dial with the amber "tight" zone at the top end.
    arc(0, 1, color: p.track, width: 78)
    arc(0.72, 1, color: p.amber, width: 78)

    // Tick marks inside the dial.
    for i in 0...10 {
        let a = angle(CGFloat(i) / 10) * .pi / 180
        let inner = r - 92, outer = r - (i % 5 == 0 ? 54 : 66)
        let tk = NSBezierPath()
        tk.move(to: NSPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
        tk.line(to: NSPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
        tk.lineWidth = i % 5 == 0 ? 14 : 9
        tk.lineCapStyle = .round
        p.tick.setStroke()
        tk.stroke()
    }

    // Needle pointing into the amber arc.
    let na = angle(0.84) * .pi / 180
    let tip = NSPoint(x: c.x + cos(na) * (r - 40), y: c.y + sin(na) * (r - 40))
    let perp = na + .pi / 2
    let needle = NSBezierPath()
    needle.move(to: tip)
    needle.line(to: NSPoint(x: c.x + cos(perp) * 26, y: c.y + sin(perp) * 26))
    needle.line(to: NSPoint(x: c.x - cos(na) * 40, y: c.y - sin(na) * 40))
    needle.line(to: NSPoint(x: c.x - cos(perp) * 26, y: c.y - sin(perp) * 26))
    needle.close()
    NSGraphicsContext.saveGraphicsState()
    let ns = NSShadow()
    ns.shadowColor = rgb(0x000000, 0.25)
    ns.shadowBlurRadius = 10
    ns.shadowOffset = NSSize(width: 0, height: -5)
    ns.set()
    p.needle.setFill()
    needle.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Hub.
    p.hub.setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - 50, y: c.y - 50, width: 100, height: 100)).fill()
    p.amber.setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - 20, y: c.y - 20, width: 40, height: 40)).fill()

    NSGraphicsContext.restoreGraphicsState()
    let out = URL(fileURLWithPath: path)
    try! FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: out)
    print("Wrote \(out.path)")
}

draw(light, tile: true, to: "icon/icon-1024.png")
draw(dark, tile: true, to: "icon/icon-1024-dark.png")
draw(light, tile: false, to: "icon/Vitals.icon/Assets/gauge-light.png")
draw(dark, tile: false, to: "icon/Vitals.icon/Assets/gauge-dark.png")
