import AppKit
import Foundation
@testable import EjectCore
@testable import UnblockEject

/// Settings in a suite of their own, so tests never touch the app's real ones.
func testPreferences() -> Preferences {
    let name = "UnblockEjectTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return Preferences(defaults: defaults)
}

struct FakeVolumes: VolumeSource {
    var all: [Volume]
    func volumes(includeHidden: Bool) -> [Volume] {
        all.filter { includeHidden || !$0.isHidden }
    }
}

/// Made-up processes, and a way to change them as a test goes, like an app quitting.
final class FakeProcesses: ProcessSource, @unchecked Sendable {
    var uses: [ProcessUse]
    var table: [Int32: ProcessFacts]

    init(uses: [ProcessUse] = [], table: [Int32: ProcessFacts] = [:]) {
        self.uses = uses
        self.table = table
    }

    func uses(of mountPoints: [String]) -> [ProcessUse] {
        uses.compactMap { use in
            let files = use.files.filter { file in mountPoints.contains { file.path == $0 || file.path.hasPrefix($0 + "/") } }
            return files.isEmpty ? nil : ProcessUse(process: use.process, files: files)
        }
    }

    func process(_ pid: Int32) -> ProcessFacts? { table[pid] }
}

/// An ejector that answers with whatever the test sets, and records what it was asked.
final class FakeEjector: Ejecting, @unchecked Sendable {
    var result: EjectResult = .ejected
    var ejected: [String] = []

    func eject(_ drive: Drive) async -> EjectResult {
        ejected.append(drive.id)
        return result
    }
}

/// Records which apps would have been asked to quit. Nothing real is ever quit in a test.
@MainActor
final class RecordedQuits: AppControl {
    var quits: [Int32] = []
    var answer = true

    func quit(_ app: AppFacts) -> Bool {
        quits.append(app.pid)
        return answer
    }
}

/// Made-up disks and apps for the tests and the README screenshots: a travel drive a photo
/// editor, a shell and Spotlight are using, a free memory card, and an installer disk image with
/// its installer still open. Every name here is invented.
enum Gallery {
    static let now = Date(timeIntervalSince1970: 1_777_560_060)

    static let ssd = Volume(path: "/Volumes/Travel SSD", name: "Travel SSD", device: "disk6s1", wholeDisk: "disk5", container: "disk6", kind: .externalDrive, size: 1_000_204_886_016)
    static let card = Volume(path: "/Volumes/FIELD REC", name: "FIELD REC", device: "disk7s1", wholeDisk: "disk7", kind: .memoryCard, size: 63_847_792_640)
    static let installer = Volume(path: "/Volumes/Brushwork 2.4", name: "Brushwork 2.4", device: "disk9s1", wholeDisk: "disk8", container: "disk9", kind: .diskImage, size: 214_958_080)
    static let hidden = Volume(path: "/Library/Developer/Volumes/Runtime", name: "Runtime", device: "disk11s1", wholeDisk: "disk10", kind: .diskImage, isHidden: true)

    static let darkroom = AppFacts(pid: 812, name: "Darkroom", bundleID: "com.example.darkroom", bundlePath: "/Applications/Darkroom.app")
    static let shellwise = AppFacts(pid: 700, name: "Shellwise", bundleID: "com.example.shellwise", bundlePath: "/Applications/Shellwise.app")
    static let brushwork = AppFacts(pid: 950, name: "Brushwork Installer", bundleID: "com.example.brushwork.installer", bundlePath: "/Volumes/Brushwork 2.4/Brushwork Installer.app")

    static var apps: [Int32: AppFacts] {
        Dictionary(uniqueKeysWithValues: [darkroom, shellwise, brushwork].map { ($0.pid, $0) })
    }

    static let darkroomProcess = ProcessFacts(pid: 812, parent: 1, name: "Darkroom", executable: "/Applications/Darkroom.app/Contents/MacOS/Darkroom")
    static let renderer = ProcessFacts(pid: 813, parent: 812, name: "Darkroom Renderer", executable: "/Applications/Darkroom.app/Contents/Frameworks/Darkroom Renderer.app/Contents/MacOS/Darkroom Renderer")
    static let login = ProcessFacts(pid: 900, parent: 700, name: "login", executable: "/usr/bin/login")
    static let zsh = ProcessFacts(pid: 901, parent: 900, name: "zsh", executable: "/bin/zsh")
    static let mdworker = ProcessFacts(pid: 55, parent: 1, name: "mdworker_shared", executable: "/System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Versions/A/Support/mdworker_shared")
    static let brushworkProcess = ProcessFacts(pid: 950, parent: 1, name: "Brushwork Installer", executable: "/Volumes/Brushwork 2.4/Brushwork Installer.app/Contents/MacOS/Brushwork Installer")

    static func use(_ process: ProcessFacts, _ files: [(String, OpenFile.Use)]) -> ProcessUse {
        ProcessUse(process: process, files: files.map { OpenFile(path: $0.0, use: $0.1) })
    }

    static var uses: [ProcessUse] {
        let shoot = "/Volumes/Travel SSD/Shoots/2026-04 Coast"
        return [
            use(darkroomProcess, [("\(shoot)/IMG_0412.raw", .file), ("\(shoot)/IMG_0418.raw", .file), ("/Volumes/Travel SSD/Catalogs/Coast.dkcat", .file)]),
            use(renderer, [("\(shoot)/IMG_0421.raw", .file), ("\(shoot)/IMG_0418.raw", .file)]),
            use(zsh, [("/Volumes/Travel SSD/Projects/tidepool-site", .folder)]),
            use(mdworker, [("\(shoot)/notes.md", .file)]),
            use(brushworkProcess, [("/Volumes/Brushwork 2.4/Brushwork Installer.app/Contents/MacOS/Brushwork Installer", .program)]),
        ]
    }

    static var table: [Int32: ProcessFacts] {
        Dictionary(uniqueKeysWithValues: [darkroomProcess, renderer, login, zsh, mdworker, brushworkProcess].map { ($0.pid, $0) })
    }

    @MainActor
    static func model(
        volumes: [Volume] = [ssd, card, installer, hidden], processes: FakeProcesses = FakeProcesses(uses: uses, table: table),
        ejector: FakeEjector = FakeEjector(), control: RecordedQuits = RecordedQuits()
    ) -> EjectModel {
        let model = EjectModel(
            volumes: FakeVolumes(all: volumes), scanner: DiskScanner(processes: processes, ownPID: nil),
            ejector: ejector, control: control, runningApps: { apps }
        )
        model.now = { now }
        model.refresh()
        return model
    }

    /// Icons for the made-up apps: a tile in the app's color with a symbol on it.
    @MainActor
    static func icons() -> AppIcons {
        let icons = AppIcons()
        icons.custom = [
            darkroom.bundlePath!: tile("camera.aperture", NSColor(srgbRed: 0.93, green: 0.55, blue: 0.20, alpha: 1), NSColor(srgbRed: 0.75, green: 0.27, blue: 0.13, alpha: 1)),
            shellwise.bundlePath!: tile("chevron.left.forwardslash.chevron.right", NSColor(srgbRed: 0.25, green: 0.28, blue: 0.33, alpha: 1), NSColor(srgbRed: 0.10, green: 0.11, blue: 0.14, alpha: 1)),
            brushwork.bundlePath!: tile("paintbrush.pointed.fill", NSColor(srgbRed: 0.55, green: 0.42, blue: 0.95, alpha: 1), NSColor(srgbRed: 0.33, green: 0.20, blue: 0.75, alpha: 1)),
        ]
        return icons
    }

    static func tile(_ symbol: String, _ top: NSColor, _ bottom: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 5, dy: 5), xRadius: 12, yRadius: 12)
            NSGradient(starting: top, ending: bottom)!.draw(in: shape, angle: -90)
            let config = NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold).applying(.init(paletteColors: [.white]))
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let size = glyph.size
                glyph.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
            }
            return true
        }
    }
}
