// Draws an app's icon the way Finder would in Light and in Dark mode, with no window (safe while Vinnie works).
//   swift scripts/icon-preview.swift [/Applications/Vitals.app] [out-folder]
// Writes icon-light.png and icon-dark.png (512 px) and prints the color at the tile's corner area and the hub,
// so a Dark mode icon can be checked without looking at the screen.
import AppKit

let app = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/Applications/Vitals.app"
let outDir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "."
let icon = NSWorkspace.shared.icon(forFile: app)
let px = 512

for (name, look) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSAppearance(named: look)!.performAsCurrentDrawingAppearance {
        icon.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    }
    NSGraphicsContext.restoreGraphicsState()
    let out = URL(fileURLWithPath: outDir).appendingPathComponent("icon-\(name).png")
    try! rep.representation(using: .png, properties: [:])!.write(to: out)
    func hex(_ x: Int, _ y: Int) -> String {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return "?" }
        return String(format: "#%02X%02X%02X a%.2f", Int(c.redComponent * 255), Int(c.greenComponent * 255),
                      Int(c.blueComponent * 255), c.alphaComponent)
    }
    // Tile: a point inside the rounded square, away from the gauge (lower left). Hub ring: just left of center, low.
    print("\(name): tile \(hex(px * 22 / 100, px * 80 / 100))  hub \(hex(px * 47 / 100, px * 58 / 100))  -> \(out.path)")
}
