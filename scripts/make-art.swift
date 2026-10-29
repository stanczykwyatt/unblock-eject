// Draws the README demo (docs/demo.gif) and the link preview image (docs/social.png).
// Everything is drawn here rather than recorded, so the art never shows anyone's real desktop or
// disks. The drive, the photo editor and its photos are all made up.
//
//   swift scripts/make-art.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

let ink = NSColor(srgbRed: 0.05, green: 0.06, blue: 0.07, alpha: 1)
let ice = NSColor(srgbRed: 0.62, green: 0.82, blue: 1.0, alpha: 1)

func bitmap(_ width: Int, _ height: Int, draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Cool silver light on a dark wallpaper, like Show Desktop's art.
func wallpaper(_ rect: NSRect) {
    NSGradient(starting: NSColor(srgbRed: 0.08, green: 0.09, blue: 0.13, alpha: 1), ending: ink)!.draw(in: rect, angle: -90)
    let glows: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
        (0.18, 0.75, 0.42, NSColor(srgbRed: 0.84, green: 0.89, blue: 0.95, alpha: 0.45)),
        (0.85, 0.72, 0.38, NSColor(srgbRed: 0.59, green: 0.68, blue: 0.81, alpha: 0.40)),
        (0.70, 0.12, 0.46, NSColor(srgbRed: 0.75, green: 0.81, blue: 0.89, alpha: 0.32)),
        (0.22, 0.15, 0.30, NSColor(srgbRed: 0.44, green: 0.53, blue: 0.65, alpha: 0.32)),
    ]
    for (x, y, r, color) in glows {
        let center = NSPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        NSGradient(starting: color, ending: color.withAlphaComponent(0))!
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: rect.width * r, options: [])
    }
}

func symbol(_ name: String, size: CGFloat, colors: [NSColor], weight: NSFont.Weight = .regular) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight).applying(.init(paletteColors: colors))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}

@discardableResult
func text(
    _ string: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white,
    centered: Bool = false, mono: Bool = false
) -> CGFloat {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let width = (string as NSString).size(withAttributes: attributes).width
    (string as NSString).draw(at: NSPoint(x: centered ? point.x - width / 2 : point.x, y: point.y), withAttributes: attributes)
    return width
}

/// A dark app window with a title bar. Returns the content area.
@discardableResult
func window(_ frame: NSRect, title: String, alpha: CGFloat = 1, scale: CGFloat = 1, key: Bool) -> NSRect {
    let rect = NSRect(
        x: frame.midX - frame.width * scale / 2, y: frame.midY - frame.height * scale / 2,
        width: frame.width * scale, height: frame.height * scale
    )
    let body = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent((key ? 0.55 : 0.35) * alpha)
    shadow.shadowBlurRadius = key ? 30 : 18
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor(srgbRed: 0.15, green: 0.16, blue: 0.19, alpha: alpha).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.12 * alpha).setStroke()
    body.lineWidth = 1
    body.stroke()
    let colors: [NSColor] = key ? [.systemRed, .systemYellow, .systemGreen] : [.gray, .gray, .gray]
    for (index, color) in colors.enumerated() {
        color.withAlphaComponent(alpha * (key ? 1 : 0.5)).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + 14 + CGFloat(index) * 18, y: rect.maxY - 22, width: 11, height: 11)).fill()
    }
    text(title, at: NSPoint(x: rect.midX, y: rect.maxY - 24), size: 12, weight: .semibold, color: .white.withAlphaComponent((key ? 0.85 : 0.45) * alpha), centered: true)
    return NSRect(x: rect.minX + 18, y: rect.minY + 14, width: rect.width - 36, height: rect.height - 50)
}

func cursor(at point: NSPoint, pressed: Bool) {
    let arrow = NSBezierPath()
    let s: CGFloat = pressed ? 0.9 : 1
    arrow.move(to: point)
    arrow.line(to: NSPoint(x: point.x, y: point.y - 22 * s))
    arrow.line(to: NSPoint(x: point.x + 5.5 * s, y: point.y - 17 * s))
    arrow.line(to: NSPoint(x: point.x + 9.5 * s, y: point.y - 25.5 * s))
    arrow.line(to: NSPoint(x: point.x + 13 * s, y: point.y - 24 * s))
    arrow.line(to: NSPoint(x: point.x + 9 * s, y: point.y - 15.5 * s))
    arrow.line(to: NSPoint(x: point.x + 16 * s, y: point.y - 15.5 * s))
    arrow.close()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.4)
    shadow.shadowBlurRadius = 3
    shadow.shadowOffset = NSSize(width: 0, height: -1)
    shadow.set()
    NSColor.black.setFill()
    arrow.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.setStroke()
    arrow.lineWidth = 1.5
    arrow.stroke()
}

// MARK: Scene

let width: CGFloat = 720
let height: CGFloat = 450
let menuBarHeight: CGFloat = 26
let iconCenter = NSPoint(x: width - 168, y: height - menuBarHeight / 2)
let editorFrame = NSRect(x: 34, y: 30, width: 470, height: 340)
let driveCenter = NSPoint(x: 616, y: 128)
let amber = NSColor(srgbRed: 0.93, green: 0.55, blue: 0.20, alpha: 1)

enum MenuState {
    case closed
    /// Darkroom has photos open on the drive.
    case blocked
    /// Nothing is using it.
    case free
    /// Ejected, and nothing left to eject.
    case done
}

struct Moment {
    var alert = false
    var okPressed = false
    var editorAlpha: CGFloat = 1
    var driveAlpha: CGFloat = 1
    var cursorAt = NSPoint(x: 360, y: 210)
    var pressed = false
    var menu = MenuState.closed
    /// The highlighted row in the menu, and whether Darkroom's submenu is open.
    var hovering: Int?
    var submenu = false
    var quitHover = false
}

/// A photo editor with a strip of photos and one open large. Plain and made up, not any real app.
func editor(_ m: Moment) {
    guard m.editorAlpha > 0 else { return }
    let content = window(editorFrame, title: "Darkroom — Coast", alpha: m.editorAlpha, key: m.menu == .closed && !m.alert)
    let photos: [(NSColor, NSColor)] = [
        (NSColor(srgbRed: 0.98, green: 0.72, blue: 0.42, alpha: 1), NSColor(srgbRed: 0.28, green: 0.44, blue: 0.62, alpha: 1)),
        (NSColor(srgbRed: 0.55, green: 0.78, blue: 0.86, alpha: 1), NSColor(srgbRed: 0.85, green: 0.78, blue: 0.62, alpha: 1)),
        (NSColor(srgbRed: 0.92, green: 0.55, blue: 0.48, alpha: 1), NSColor(srgbRed: 0.20, green: 0.25, blue: 0.40, alpha: 1)),
        (NSColor(srgbRed: 0.70, green: 0.84, blue: 0.80, alpha: 1), NSColor(srgbRed: 0.32, green: 0.52, blue: 0.48, alpha: 1)),
    ]
    func photo(_ rect: NSRect, _ colors: (NSColor, NSColor), radius: CGFloat) {
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGradient(starting: colors.0.withAlphaComponent(m.editorAlpha), ending: colors.1.withAlphaComponent(m.editorAlpha))!.draw(in: shape, angle: -90)
        // A horizon, so each reads as a landscape.
        colors.1.blended(withFraction: 0.4, of: .black)!.withAlphaComponent(0.55 * m.editorAlpha).setFill()
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.32)).fill()
    }
    let strip = NSRect(x: content.minX, y: content.minY, width: 92, height: content.height)
    for (index, colors) in photos.enumerated() {
        let rect = NSRect(x: strip.minX, y: strip.maxY - 64 - CGFloat(index) * 72, width: 92, height: 62)
        photo(rect, colors, radius: 5)
        if index == 0 {
            amber.withAlphaComponent(m.editorAlpha).setStroke()
            let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), xRadius: 6, yRadius: 6)
            ring.lineWidth = 2
            ring.stroke()
        }
    }
    let large = NSRect(x: strip.maxX + 14, y: content.minY + 26, width: content.maxX - strip.maxX - 14, height: content.height - 26)
    photo(large, photos[0], radius: 7)
    text("IMG_0412.raw · Travel SSD", at: NSPoint(x: large.minX, y: content.minY + 4), size: 10.5, color: .white.withAlphaComponent(0.5 * m.editorAlpha))
}

/// The drive's icon on the desktop.
func driveIcon(_ m: Moment) {
    guard m.driveAlpha > 0 else { return }
    let body = NSRect(x: driveCenter.x - 26, y: driveCenter.y - 12, width: 52, height: 26)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.4 * m.driveAlpha)
    shadow.shadowBlurRadius = 6
    shadow.shadowOffset = NSSize(width: 0, height: -3)
    shadow.set()
    NSColor(srgbRed: 0.88, green: 0.90, blue: 0.93, alpha: m.driveAlpha).setFill()
    NSBezierPath(roundedRect: body, xRadius: 6, yRadius: 6).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor(srgbRed: 0.13, green: 0.17, blue: 0.27, alpha: 0.8 * m.driveAlpha).setFill()
    NSBezierPath(ovalIn: NSRect(x: body.maxX - 12, y: body.midY - 3, width: 6, height: 6)).fill()
    text("Travel SSD", at: NSPoint(x: driveCenter.x, y: driveCenter.y - 32), size: 11, weight: .medium, color: .white.withAlphaComponent(m.driveAlpha), centered: true)
}

let alertRect = NSRect(x: width / 2 - 150, y: 168, width: 300, height: 128)
let okRect = NSRect(x: alertRect.maxX - 78, y: alertRect.minY + 14, width: 64, height: 24)

/// The alert you get when a disk won't eject, drawn plainly.
func alert(_ m: Moment) {
    guard m.alert else { return }
    panel(alertRect)
    symbol("exclamationmark.triangle.fill", size: 22, colors: [.systemYellow]).draw(at: NSPoint(x: alertRect.minX + 18, y: alertRect.maxY - 44), from: .zero, operation: .sourceOver, fraction: 1)
    text("“Travel SSD” wasn't ejected", at: NSPoint(x: alertRect.minX + 54, y: alertRect.maxY - 36), size: 13, weight: .semibold)
    text("Something on your Mac is still using it,", at: NSPoint(x: alertRect.minX + 54, y: alertRect.maxY - 58), size: 11.5, color: .white.withAlphaComponent(0.7))
    text("but it doesn't say what.", at: NSPoint(x: alertRect.minX + 54, y: alertRect.maxY - 74), size: 11.5, color: .white.withAlphaComponent(0.7))
    (m.okPressed ? NSColor.systemBlue.blended(withFraction: 0.3, of: .black)! : NSColor.systemBlue).setFill()
    NSBezierPath(roundedRect: okRect, xRadius: 6, yRadius: 6).fill()
    text("OK", at: NSPoint(x: okRect.midX, y: okRect.minY + 5), size: 12, weight: .medium, centered: true)
}

func scene(_ m: Moment) {
    wallpaper(NSRect(x: 0, y: 0, width: width, height: height))
    driveIcon(m)
    editor(m)

    // The menu bar.
    NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 0.72).setFill()
    NSRect(x: 0, y: height - menuBarHeight, width: width, height: menuBarHeight).fill()
    if m.editorAlpha > 0.5 {
        text("Darkroom", at: NSPoint(x: 18, y: height - 19), size: 12.5, weight: .bold)
        for (index, word) in ["File", "Edit", "Photo", "Window"].enumerated() {
            text(word, at: NSPoint(x: 96 + CGFloat(index) * 46, y: height - 19), size: 12.5)
        }
    }
    if m.pressed || m.menu != .closed {
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: NSRect(x: iconCenter.x - 15, y: height - menuBarHeight + 3, width: 30, height: menuBarHeight - 6), xRadius: 5, yRadius: 5).fill()
    }
    statusIcon(at: iconCenter)
    for (index, name) in ["wifi", "magnifyingglass", "switch.2"].enumerated() {
        let image = symbol(name, size: 13, colors: [.white])
        image.draw(at: NSPoint(x: width - 128 + CGFloat(index) * 30, y: height - 20), from: .zero, operation: .sourceOver, fraction: 1)
    }
    text("9:41", at: NSPoint(x: width - 40, y: height - 19), size: 12.5, weight: .medium)

    alert(m)
    if m.menu != .closed { menu(m) }
    cursor(at: m.cursorAt, pressed: m.pressed)
}

/// The app's menu bar icon, drawn as in the app: the eject symbol.
func statusIcon(at center: NSPoint) {
    NSColor.white.set()
    let triangle = NSBezierPath()
    triangle.move(to: NSPoint(x: center.x - 6, y: center.y - 1.4))
    triangle.line(to: NSPoint(x: center.x + 6, y: center.y - 1.4))
    triangle.line(to: NSPoint(x: center.x, y: center.y + 6))
    triangle.close()
    triangle.lineJoinStyle = .round
    triangle.lineWidth = 1.2
    triangle.fill()
    triangle.stroke()
    NSBezierPath(roundedRect: NSRect(x: center.x - 6, y: center.y - 6, width: 12, height: 2.2), xRadius: 1.1, yRadius: 1.1).fill()
}

func panel(_ rect: NSRect) {
    let body = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.5)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    NSColor(srgbRed: 0.17, green: 0.18, blue: 0.21, alpha: 1).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.14).setStroke()
    body.lineWidth = 1
    body.stroke()
}

func separator(_ rect: NSRect, y: CGFloat) {
    NSColor.white.withAlphaComponent(0.12).setFill()
    NSRect(x: rect.minX + 10, y: y, width: rect.width - 20, height: 1).fill()
}

func highlight(_ rect: NSRect, y: CGFloat, height: CGFloat = 24) {
    NSColor.systemBlue.withAlphaComponent(0.85).setFill()
    NSBezierPath(roundedRect: NSRect(x: rect.minX + 6, y: y, width: rect.width - 12, height: height), xRadius: 6, yRadius: 6).fill()
}

/// A made-up app's icon: an amber tile with an aperture, as in the screenshots.
func darkroomIcon(at point: NSPoint, size: CGFloat) {
    let rect = NSRect(x: point.x, y: point.y, width: size, height: size)
    NSGradient(starting: amber, ending: NSColor(srgbRed: 0.75, green: 0.27, blue: 0.13, alpha: 1))!
        .draw(in: NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22), angle: -90)
    symbol("camera.aperture", size: size * 0.55, colors: [.white], weight: .semibold)
        .draw(at: NSPoint(x: rect.minX + size * 0.2, y: rect.minY + size * 0.18), from: .zero, operation: .sourceOver, fraction: 1)
}

let menuWidth: CGFloat = 286
let menuRect = NSRect(x: width - 8 - menuWidth, y: height - menuBarHeight - 4 - 196, width: menuWidth, height: 196)
/// Where each row's text sits, from the top.
let rowY: [CGFloat] = [menuRect.maxY - 70, menuRect.maxY - 112]
let submenuRect = NSRect(x: menuRect.minX - 236, y: rowY[0] - 116, width: 230, height: 142)
let quitRowY = submenuRect.minY + 14

/// The app's menu, drawn as it looks open.
func menu(_ m: Moment) {
    // With nothing left to eject, the menu is shorter.
    let menuRect = m.menu == .done ? NSRect(x: menuRect.minX, y: menuRect.maxY - 148, width: menuRect.width, height: 148) : menuRect
    panel(menuRect)
    let left = menuRect.minX + 14
    var y = menuRect.maxY - 24
    if m.menu == .done {
        text("Ejected “Travel SSD”.", at: NSPoint(x: left, y: y), size: 13, color: .white.withAlphaComponent(0.55))
        y -= 17
        text("It's safe to unplug.", at: NSPoint(x: left, y: y), size: 13, color: .white.withAlphaComponent(0.55))
        separator(menuRect, y: y - 10)
        y -= 34
        text("No disks to eject", at: NSPoint(x: left, y: y), size: 13, color: .white.withAlphaComponent(0.45))
    } else {
        text("Travel SSD", at: NSPoint(x: left, y: y), size: 11, weight: .bold, color: .white.withAlphaComponent(0.5))
        y -= 17
        let status = m.menu == .blocked ? "External drive · 1 TB · In use by Darkroom" : "External drive · 1 TB · Nothing is using it"
        text(status, at: NSPoint(x: left, y: y), size: 11, color: .white.withAlphaComponent(0.42))
        if m.menu == .blocked {
            if m.hovering == 0 { highlight(menuRect, y: rowY[0] - 13, height: 36) }
            darkroomIcon(at: NSPoint(x: left, y: rowY[0] - 8), size: 20)
            text("Darkroom", at: NSPoint(x: left + 28, y: rowY[0] + 4), size: 13)
            text("4 files open", at: NSPoint(x: left + 28, y: rowY[0] - 10), size: 10.5, color: .white.withAlphaComponent(m.hovering == 0 ? 0.8 : 0.45))
            text("›", at: NSPoint(x: menuRect.maxX - 22, y: rowY[0]), size: 13, color: .white.withAlphaComponent(0.5))
        }
        let ejectY = m.menu == .blocked ? rowY[1] : rowY[0]
        if m.hovering == 1 { highlight(menuRect, y: ejectY - 5) }
        symbol("eject", size: 12, colors: [.white]).draw(at: NSPoint(x: left, y: ejectY + 1), from: .zero, operation: .sourceOver, fraction: 1)
        text("Eject “Travel SSD”", at: NSPoint(x: left + 22, y: ejectY), size: 13, weight: m.hovering == 1 ? .medium : .regular)
        y = ejectY
    }
    separator(menuRect, y: menuRect.minY + 60)
    text("Open Unblock Eject…", at: NSPoint(x: left, y: menuRect.minY + 36), size: 13)
    text("⌘O", at: NSPoint(x: menuRect.maxX - 40, y: menuRect.minY + 36), size: 13, color: .white.withAlphaComponent(0.5))
    text("Open at Login", at: NSPoint(x: left, y: menuRect.minY + 12), size: 13)

    guard m.submenu else { return }
    panel(submenuRect)
    let subLeft = submenuRect.minX + 14
    var line = submenuRect.maxY - 24
    for file in ["Catalogs/Coast.dkcat", "Coast/IMG_0412.raw", "Coast/IMG_0418.raw", "Coast/IMG_0421.raw"] {
        text(file, at: NSPoint(x: subLeft, y: line), size: 11.5, color: .white.withAlphaComponent(0.45))
        line -= 19
    }
    separator(submenuRect, y: quitRowY + 26)
    if m.quitHover { highlight(submenuRect, y: quitRowY - 5) }
    text("Quit Darkroom", at: NSPoint(x: subLeft, y: quitRowY), size: 13, weight: m.quitHover ? .medium : .regular)
}

// MARK: Demo

func lerp(_ a: NSPoint, _ b: NSPoint, _ t: CGFloat) -> NSPoint {
    let e = t * t * (3 - 2 * t)
    return NSPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e)
}

var frames: [(NSBitmapImageRep, Double)] = []
func frame(_ m: Moment, hold: Double = 0.07) {
    // Drawn at 2x so the GIF looks sharp on Retina screens when shown at 720 points.
    let rep = bitmap(Int(width * 2), Int(height * 2)) {
        let transform = NSAffineTransform()
        transform.scale(by: 2)
        transform.concat()
        scene(m)
    }
    frames.append((rep, hold))
}

var m = Moment()
m.alert = true
m.cursorAt = NSPoint(x: okRect.midX - 30, y: okRect.midY - 40)
frame(m, hold: 1.8)
// The usual alert: it won't eject, and macOS doesn't say why.
var from = m.cursorAt
for step in 1...8 {
    m.cursorAt = lerp(from, NSPoint(x: okRect.midX, y: okRect.midY + 4), CGFloat(step) / 8)
    frame(m, hold: 0.04)
}
m.okPressed = true
frame(m, hold: 0.12)
m.okPressed = false
m.alert = false
frame(m, hold: 0.4)
// Unblock Eject's menu says what: Darkroom has four photos open on it.
let onIcon = NSPoint(x: iconCenter.x - 2, y: iconCenter.y + 6)
from = m.cursorAt
for step in 1...12 {
    m.cursorAt = lerp(from, onIcon, CGFloat(step) / 12)
    frame(m, hold: 0.04)
}
m.pressed = true
frame(m, hold: 0.12)
m.pressed = false
m.menu = .blocked
frame(m, hold: 1.2)
let onDarkroom = NSPoint(x: menuRect.minX + 90, y: rowY[0] + 4)
from = m.cursorAt
for step in 1...8 {
    m.cursorAt = lerp(from, onDarkroom, CGFloat(step) / 8)
    frame(m, hold: 0.04)
}
m.hovering = 0
m.submenu = true
frame(m, hold: 1.4)
let onQuit = NSPoint(x: submenuRect.minX + 70, y: quitRowY + 8)
from = m.cursorAt
for step in 1...10 {
    m.cursorAt = lerp(from, onQuit, CGFloat(step) / 10)
    frame(m, hold: 0.04)
}
m.quitHover = true
frame(m, hold: 0.6)
m.pressed = true
frame(m, hold: 0.1)
// Darkroom quits the normal way.
m.pressed = false
m.menu = .closed
m.hovering = nil
m.submenu = false
m.quitHover = false
for alpha in stride(from: 0.8, through: 0, by: -0.2) {
    m.editorAlpha = CGFloat(alpha)
    frame(m, hold: 0.06)
}
frame(m, hold: 0.5)
// Now it's free: eject.
from = m.cursorAt
for step in 1...12 {
    m.cursorAt = lerp(from, onIcon, CGFloat(step) / 12)
    frame(m, hold: 0.04)
}
m.pressed = true
frame(m, hold: 0.12)
m.pressed = false
m.menu = .free
frame(m, hold: 0.9)
let onEject = NSPoint(x: menuRect.minX + 90, y: rowY[0] + 8)
from = m.cursorAt
for step in 1...8 {
    m.cursorAt = lerp(from, onEject, CGFloat(step) / 8)
    frame(m, hold: 0.04)
}
m.hovering = 1
frame(m, hold: 0.6)
m.pressed = true
frame(m, hold: 0.1)
m.pressed = false
m.menu = .closed
m.hovering = nil
for alpha in stride(from: 0.75, through: 0, by: -0.25) {
    m.driveAlpha = CGFloat(alpha)
    frame(m, hold: 0.06)
}
from = m.cursorAt
for step in 1...6 {
    m.cursorAt = lerp(from, onIcon, CGFloat(step) / 6)
    frame(m, hold: 0.04)
}
m.menu = .done
frame(m, hold: 3.6)

let gifURL = URL(fileURLWithPath: "docs/demo.gif")
let destination = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for (rep, hold) in frames {
    CGImageDestinationAddImage(destination, rep.cgImage!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: hold]] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write the GIF") }

// The last frame on its own, for checking the art without playing the GIF.
if let preview = ProcessInfo.processInfo.environment["PREVIEW"] {
    try frames.last!.0.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: preview))
}

// MARK: Link preview

let social = bitmap(1280, 640) {
    let rect = NSRect(x: 0, y: 0, width: 1280, height: 640)
    wallpaper(rect)
    if let icon = NSImage(contentsOfFile: "docs/icon.png") {
        icon.draw(in: NSRect(x: 640 - 80, y: 380, width: 160, height: 160))
    }
    text("Unblock Eject", at: NSPoint(x: 640, y: 270), size: 84, weight: .semibold, centered: true)
    text("See what's keeping your disk from ejecting.", at: NSPoint(x: 640, y: 205), size: 30, color: .white.withAlphaComponent(0.75), centered: true)
    text("free · open source · never force-quits · no internet access", at: NSPoint(x: 640, y: 120), size: 22, weight: .medium, color: .white.withAlphaComponent(0.5), centered: true)
}
try social.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/social.png"))
print("Wrote docs/demo.gif and docs/social.png")
