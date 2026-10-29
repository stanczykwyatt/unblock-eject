import AppKit
import Foundation
import SwiftUI
import Testing
@testable import EjectCore
@testable import UnblockEject

/// Renders the window into a bitmap from a window that's never shown, so nothing appears on screen
/// or takes focus. Set SCREENSHOT_DIR to also save the renders as the README screenshots:
///
///   SCREENSHOT_DIR=docs swift test --filter "WindowTests"
@MainActor
@Suite("Window")
struct WindowTests {
    static let size = NSSize(width: 940, height: 730)

    private func view(_ model: EjectModel) -> EjectView {
        EjectView(model: model, icons: Gallery.icons(), now: { Gallery.now.addingTimeInterval(4) }, tint: Color(red: 0.24, green: 0.47, blue: 0.86))
    }

    /// The README's story: Travel SSD wouldn't eject, and here's who has it.
    private func galleryModel() async -> EjectModel {
        let ejector = FakeEjector()
        ejector.result = .busy(message: nil)
        let model = Gallery.model(ejector: ejector)
        await model.eject(model.report("disk5")!.drive)
        return model
    }

    @Test func rendersTheDisks() async {
        let image = render(view(await galleryModel()), name: "screenshot-light", dark: false)
        #expect(image.pixelsWide >= Int(Self.size.width))
        #expect(colors(in: image) > 30)
    }

    @Test func rendersInDarkMode() async {
        #expect(colors(in: render(view(await galleryModel()), name: "screenshot-dark", dark: true)) > 20)
    }

    @Test func rendersTheOtherStates() async {
        #expect(colors(in: render(view(Gallery.model(volumes: [])), name: nil, dark: false)) > 4)
        #expect(colors(in: render(view(Gallery.model(volumes: [Gallery.card])), name: nil, dark: true)) > 4)
        let model = Gallery.model()
        await model.eject(model.report("disk7")!.drive)
        model.quit(model.report("disk5")!.blockers[0])
        #expect(colors(in: render(view(model), name: nil, dark: false)) > 8)
    }

    @Test func everySymbolExists() {
        var names = ["eject", "eject.fill", "arrow.clockwise", "exclamationmark.triangle.fill", "checkmark.circle.fill", "xmark", "hand.raised",
                     "terminal", "gearshape.2", "camera.aperture", "chevron.left.forwardslash.chevron.right", "paintbrush.pointed.fill"]
        names += SystemProcess.allCases.map(AppIcons.symbolName)
        names += [Volume.Kind.externalDrive, .memoryCard, .diskImage].map(AppIcons.symbolName)
        for symbol in names {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "Missing symbol \(symbol)")
        }
    }

    @Test func blockerIcons() {
        let icons = Gallery.icons()
        let model = Gallery.model()
        for blocker in model.reports.flatMap(\.blockers) {
            let icon = icons.icon(for: blocker, size: 32)
            #expect(icon.size == NSSize(width: 32, height: 32))
            #expect(icon.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil)
        }
        // A real app on disk gets its own icon, and a shell without one gets a terminal.
        let finder = Blocker(id: "f", kind: .finder, name: "Finder", app: nil, iconPath: "/System/Library/CoreServices/Finder.app", processes: [], files: [])
        #expect(AppIcons().icon(for: finder, size: 16).size.width == 16)
        let shell = Blocker(id: "s", kind: .shell(in: "X"), name: "zsh", app: nil, iconPath: nil, processes: [], files: [])
        #expect(AppIcons().icon(for: shell, size: 16).isValid)
    }

    @Test func theMenuBarIconIsATemplate() {
        for alert in [false, true] {
            let image = StatusIcon.image(alert: alert)
            #expect(image.isTemplate && image.size == NSSize(width: 18, height: 18))
            #expect(image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil)
        }
    }

    // MARK: Rendering

    private func render(_ view: EjectView, name: String?, dark: Bool, size: NSSize = WindowTests.size) -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        // Never ordered front: it only gives the view a backing to draw into.
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: image)
        if let name, let folder = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
            try? image.representation(using: .png, properties: [:])?.write(to: url)
        }
        return image
    }

    /// Distinct colors in a coarse grid: a blank or broken render has only a few.
    private func colors(in image: NSBitmapImageRep) -> Int {
        var seen = Set<UInt32>()
        for x in stride(from: 0, to: image.pixelsWide, by: 7) {
            for y in stride(from: 0, to: image.pixelsHigh, by: 7) {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let r = UInt32(color.redComponent * 31), g = UInt32(color.greenComponent * 31), b = UInt32(color.blueComponent * 31)
                seen.insert(r << 10 | g << 5 | b)
            }
        }
        return seen.count
    }
}

/// The app's bundle settings and signing, checked against what the docs promise.
@Suite("Bundle")
struct BundleTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func aMenuBarAppWithItsOwnID() throws {
        let info = try #require(NSDictionary(contentsOf: Self.root.appendingPathComponent("Resources/Info.plist")) as? [String: Any])
        #expect(info["CFBundleIdentifier"] as? String == "com.stanczykwyatt.UnblockEject")
        #expect(info["LSUIElement"] as? Bool == true)
        #expect(info["CFBundleShortVersionString"] as? String == Command.toolVersion)
        #expect(info["LSMinimumSystemVersion"] as? String == "14.0")
    }

    @Test func noEntitlementsAndTheDefaultSignature() throws {
        // Nothing to grant: no entitlements file, and the build signs with the hardened runtime
        // and macOS's default requirement, never one that trusts the bundle ID alone.
        let resources = try FileManager.default.contentsOfDirectory(atPath: Self.root.appendingPathComponent("Resources").path)
        #expect(!resources.contains { $0.hasSuffix(".entitlements") })
        let script = try String(contentsOf: Self.root.appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)
        #expect(script.contains("--options runtime"))
        #expect(!script.contains("--entitlements"))
        #expect(!script.contains("--requirements"))
        #expect(!script.contains("designated =>"))
    }
}
