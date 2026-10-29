import AppKit
import EjectCore

/// Icons for blockers and disks, looked up once each.
@MainActor
final class AppIcons {
    private var cache: [String: NSImage] = [:]
    /// Icons to use instead of looking them up, by app path. Used for the README screenshots,
    /// whose made-up apps have no icons of their own.
    var custom: [String: NSImage] = [:]

    func icon(for blocker: Blocker, size: CGFloat) -> NSImage {
        let key = "\(blocker.iconPath ?? blocker.id)@\(size)"
        if let cached = cache[key] { return cached }
        let icon = (source(for: blocker).copy() as? NSImage) ?? NSImage()
        icon.size = NSSize(width: size, height: size)
        cache[key] = icon
        return icon
    }

    private func source(for blocker: Blocker) -> NSImage {
        if let path = blocker.iconPath, let image = custom[path] { return image }
        if case .system(let system) = blocker.kind, blocker.app == nil {
            return Self.symbol(Self.symbolName(system))
        }
        if let path = blocker.iconPath, FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        switch blocker.kind {
        case .shell, .command: return Self.symbol("terminal")
        default: return Self.symbol("gearshape.2")
        }
    }

    static func symbolName(_ system: SystemProcess) -> String {
        switch system {
        case .spotlight: "magnifyingglass"
        case .timeMachine: "clock.arrow.circlepath"
        case .quickLook: "eye"
        case .photos: "photo.on.rectangle"
        case .mediaLibrary: "music.note"
        case .diskImage: "doc.zipper"
        case .securityCheck: "checkmark.shield"
        case .macOS: "gearshape.2"
        }
    }

    static func symbolName(_ kind: Volume.Kind) -> String {
        switch kind {
        case .externalDrive: "externaldrive.fill"
        case .memoryCard: "sdcard.fill"
        case .diskImage: "doc.zipper"
        }
    }

    static func symbol(_ name: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 26, weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage()
    }
}
