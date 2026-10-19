import AppKit

/// `Vitals --render menubar <out.png> [light|dark]`: every state the menu bar item can show, each on a
/// real status bar button hosted off screen at the item's fixed width, on a menu-bar-coloured strip with
/// a caption under it. Drawn at 3x.
@MainActor
enum MenuBarPreview {
    static func render(to path: String, dark: Bool) -> Bool {
        _ = NSApplication.shared
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let bar = dark ? NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1) : NSColor(srgbRed: 0.91, green: 0.91, blue: 0.92, alpha: 1)
        let ink = dark ? NSColor(white: 0.85, alpha: 1) : NSColor(white: 0.2, alpha: 1)
        let states = StatusIcon.allStates
        let scale: CGFloat = 3, row: CGFloat = 24, cell: CGFloat = 76, caption: CGFloat = 26, margin: CGFloat = 8

        // Measure the fixed width on a button of our own, as the app does.
        let probe = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 100, height: row))
        let width = StatusIcon.fixedLength(for: probe)

        var placed: [(NSWindow, NSRect)] = []
        for (i, state) in states.enumerated() {
            let window = NSWindow(contentRect: NSRect(x: -40000, y: -40000, width: width, height: row),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = appearance
            window.backgroundColor = bar
            let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: width, height: row))
            window.contentView = Swatch(frame: button.frame, color: bar)
            window.contentView?.addSubview(button)
            StatusIcon.apply(state, to: button)
            let x = margin + CGFloat(i) * cell + (cell - width) / 2
            placed.append((window, NSRect(x: x, y: margin + caption, width: width, height: row)))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3)) // let the buttons lay out

        let size = NSSize(width: margin * 2 + cell * CGFloat(states.count), height: margin * 2 + caption + row)
        guard let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              case _ = { sheet.size = size }(), // in points, before the context is made from it
              let context = NSGraphicsContext(bitmapImageRep: sheet) else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        (dark ? NSColor(white: 0.1, alpha: 1) : NSColor.white).setFill()
        NSRect(origin: .zero, size: size).fill()
        bar.setFill()
        NSRect(x: margin, y: margin + caption, width: size.width - margin * 2, height: row).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8.5), .foregroundColor: ink]
        for (i, state) in states.enumerated() {
            let (window, frame) = placed[i]
            if let content = window.contentView, let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(frame.width * scale), pixelsHigh: Int(frame.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0) {
                rep.size = frame.size
                content.cacheDisplay(in: content.bounds, to: rep)
                rep.draw(in: frame)
            }
            let text = NSString(string: label(state))
            let w = text.size(withAttributes: attrs).width
            text.draw(at: NSPoint(x: margin + CGFloat(i) * cell + (cell - w) / 2, y: margin + 6), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = sheet.representation(using: .png, properties: [:]), (try? png.write(to: URL(fileURLWithPath: path))) != nil else {
            return false
        }
        print("Rendered menubar (\(dark ? "dark" : "light"), \(Int(width)) pt per state) to \(path)")
        return true
    }

    private static func label(_ s: StatusIcon.State) -> String {
        guard let area = s.area else { return "calm" }
        let name = area == .disk ? "disk" : area == .heat ? "heat" : area.name
        return "\(name) \(s.severity == .critical ? "crit" : "warn")"
    }
}

/// A flat colour behind a preview button (a window's own background isn't part of its view's cache).
private final class Swatch: NSView {
    private let color: NSColor
    init(frame: NSRect, color: NSColor) { self.color = color; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) { color.setFill(); bounds.fill() }
}
