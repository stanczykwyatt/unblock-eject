import AppKit

/// The menu bar icon: the eject symbol, a triangle over a bar, with a dot when an eject failed.
enum StatusIcon {
    static func image(alert: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.set()
            let shift: CGFloat = alert ? -1.5 : 0
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: 3 + shift, y: 7.6))
            triangle.line(to: NSPoint(x: 15 + shift, y: 7.6))
            triangle.line(to: NSPoint(x: 9 + shift, y: 15))
            triangle.close()
            triangle.lineJoinStyle = .round
            triangle.lineWidth = 1.2
            triangle.fill()
            triangle.stroke()
            NSBezierPath(roundedRect: NSRect(x: 3 + shift, y: 3, width: 12, height: 2.2), xRadius: 1.1, yRadius: 1.1).fill()
            if alert {
                NSBezierPath(ovalIn: NSRect(x: rect.maxX - 5, y: rect.maxY - 5.5, width: 5, height: 5)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = alert ? "Unblock Eject, couldn't eject a disk" : "Unblock Eject"
        return image
    }
}
