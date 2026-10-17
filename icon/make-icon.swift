// Draws the Vitals app icon: a gray gauge whose needle sits in an amber arc, on a rounded square.
// Run from the vitals folder:  swift icon/make-icon.swift   (writes icon/icon-1024.png)
import AppKit

let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: S, height: S)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

// macOS icon grid: 824 body, inset 100.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

// Soft drop shadow under the body.
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = rgb(0x000000, 0.28)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
rgb(0xEDEBE6).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

// Warm off-white body, like the app's light theme.
NSGradient(starting: rgb(0xFBFAF7), ending: rgb(0xE4E1DA))!.draw(in: shape, angle: -90)
rgb(0x000000, 0.08).setStroke()
let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 184.5, yRadius: 184.5)
rim.lineWidth = 3
rim.stroke()

let c = NSPoint(x: 512, y: 430)
let r: CGFloat = 270
let start: CGFloat = 200, end: CGFloat = -20   // degrees, sweeping clockwise over the top
func angle(_ t: CGFloat) -> CGFloat { start - (start - end) * t }   // t: 0…1 along the dial

func arc(_ t0: CGFloat, _ t1: CGFloat, color: NSColor, width: CGFloat) {
    let p = NSBezierPath()
    p.appendArc(withCenter: c, radius: r, startAngle: angle(t0), endAngle: angle(t1), clockwise: true)
    p.lineWidth = width
    p.lineCapStyle = .round
    color.setStroke()
    p.stroke()
}

// Gray dial with the amber "tight" zone at the top end.
arc(0, 1, color: rgb(0xB9B6AE), width: 78)
arc(0.72, 1, color: rgb(0xE09A1D), width: 78)

// Tick marks inside the dial.
for i in 0...10 {
    let a = angle(CGFloat(i) / 10) * .pi / 180
    let inner = r - 92, outer = r - (i % 5 == 0 ? 54 : 66)
    let p = NSBezierPath()
    p.move(to: NSPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
    p.line(to: NSPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
    p.lineWidth = i % 5 == 0 ? 14 : 9
    p.lineCapStyle = .round
    rgb(0x8E8B84).setStroke()
    p.stroke()
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
rgb(0x4A4844).setFill()
needle.fill()
NSGraphicsContext.restoreGraphicsState()

// Hub.
rgb(0x4A4844).setFill()
NSBezierPath(ovalIn: NSRect(x: c.x - 50, y: c.y - 50, width: 100, height: 100)).fill()
rgb(0xE09A1D).setFill()
NSBezierPath(ovalIn: NSRect(x: c.x - 20, y: c.y - 20, width: 40, height: 40)).fill()

NSGraphicsContext.restoreGraphicsState()
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon/icon-1024.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
