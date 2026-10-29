// Draws the app icon and writes it to Resources/AppIcon.icns, plus docs/icon.png for the website.
//
//   swift scripts/make-icon.swift
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns"

/// Draws the icon on a 1024-point canvas, scaled to `pixels`.
func icon(pixels: Int) -> NSBitmapImageRep {
    let image = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(pixels) / 1024)
    scale.concat()

    let slate = NSColor(srgbRed: 0.13, green: 0.17, blue: 0.27, alpha: 1)
    let ice = NSColor(srgbRed: 0.62, green: 0.82, blue: 1.0, alpha: 1)

    // The rounded tile, with the soft shadow macOS icons sit on. Same tile and light as Show Desktop.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowColor = .black.withAlphaComponent(0.3)
    tileShadow.shadowBlurRadius = 24
    tileShadow.shadowOffset = NSSize(width: 0, height: -12)
    tileShadow.set()
    slate.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [
        NSColor(srgbRed: 0.80, green: 0.87, blue: 0.96, alpha: 1),
        NSColor(srgbRed: 0.45, green: 0.57, blue: 0.75, alpha: 1),
        slate,
    ])!.draw(in: tile, angle: -90)

    /// A rounded bar, with a soft shadow, or glowing in `color` when it's the newest part.
    func bar(_ rect: NSRect, color: NSColor, glow: Bool) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        if glow {
            shadow.shadowColor = color.withAlphaComponent(0.75)
            shadow.shadowBlurRadius = 34
        } else {
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
            shadow.shadowBlurRadius = 10
            shadow.shadowOffset = NSSize(width: 0, height: -6)
        }
        shadow.set()
        color.setFill()
        let radius = min(rect.width, rect.height) / 2
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The drive: a white body with rounded corners and a soft shadow.
    func sheet(_ rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set()
        NSColor.white.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 46, yRadius: 46).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    // The eject symbol, glowing in ice blue against the slate, over a drive: a white body with a
    // slate light and vents, the way an external drive sits on a desk.
    let drive = NSRect(x: 214, y: 196, width: 596, height: 236)
    sheet(drive)
    bar(NSRect(x: 690, y: 296, width: 50, height: 36), color: slate.withAlphaComponent(0.85), glow: false)
    for index in 0..<3 {
        bar(NSRect(x: 290 + CGFloat(index) * 70, y: 300, width: 44, height: 28), color: slate.withAlphaComponent(0.4), glow: false)
    }
    let triangle = NSBezierPath()
    triangle.move(to: NSPoint(x: 512, y: 828))
    triangle.line(to: NSPoint(x: 722, y: 598))
    triangle.line(to: NSPoint(x: 302, y: 598))
    triangle.close()
    triangle.lineJoinStyle = .round
    triangle.lineWidth = 36
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = ice.withAlphaComponent(0.8)
    glow.shadowBlurRadius = 36
    glow.set()
    ice.setFill()
    ice.setStroke()
    triangle.fill()
    triangle.stroke()
    NSGraphicsContext.restoreGraphicsState()
    bar(NSRect(x: 284, y: 494, width: 456, height: 58), color: ice, glow: true)

    NSGraphicsContext.restoreGraphicsState()
    return image
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = icon(pixels: points * scale).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}
try icon(pixels: 256).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/icon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", iconset.path, "--output", output]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
Swift.print("Wrote \(output) and docs/icon.png")
