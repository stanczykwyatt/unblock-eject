import Foundation
@testable import EjectCore

/// Made-up processes, so tests never look at what's really running.
struct FakeProcesses: ProcessSource {
    var uses: [ProcessUse] = []
    /// Every process by ID, for walking parents.
    var table: [Int32: ProcessFacts] = [:]

    func uses(of mountPoints: [String]) -> [ProcessUse] {
        uses.compactMap { use in
            let files = use.files.filter { file in mountPoints.contains { Paths.isInside(file.path, $0) } }
            return files.isEmpty ? nil : ProcessUse(process: use.process, files: files)
        }
    }

    func process(_ pid: Int32) -> ProcessFacts? { table[pid] }
}

/// Made-up volumes, for the parts of the tool that list disks.
struct FakeVolumes: VolumeSource {
    var all: [Volume]
    func volumes(includeHidden: Bool) -> [Volume] {
        all.filter { includeHidden || !$0.isHidden }
    }
}

enum Sample {
    static let travel = Volume(path: "/Volumes/Travel SSD", name: "Travel SSD", device: "disk6s1", wholeDisk: "disk6", kind: .externalDrive, size: 1_000_000_000_000)
    static let card = Volume(path: "/Volumes/FIELD REC", name: "FIELD REC", device: "disk7s1", wholeDisk: "disk7", kind: .memoryCard, size: 64_000_000_000)
    static let installer = Volume(path: "/Volumes/Brushwork", name: "Brushwork", device: "disk8s1", wholeDisk: "disk8", kind: .diskImage, size: 210_000_000)
    static let hidden = Volume(path: "/private/tmp/scratch", name: "Scratch", device: "disk9s1", wholeDisk: "disk9", kind: .diskImage, isHidden: true)
    static let backupA = Volume(path: "/Volumes/Archive", name: "Archive", device: "disk10s1", wholeDisk: "disk10", kind: .externalDrive)
    static let backupB = Volume(path: "/Volumes/Archive 2", name: "Archive 2", device: "disk10s2", wholeDisk: "disk10", kind: .externalDrive)

    static let travelDrive = Drive(wholeDisk: "disk6", volumes: [travel])
    static let archiveDrive = Drive(wholeDisk: "disk10", volumes: [backupA, backupB])

    static let darkroom = AppFacts(pid: 812, name: "Darkroom", bundleID: "com.example.darkroom", bundlePath: "/Applications/Darkroom.app")
    static let shellwise = AppFacts(pid: 700, name: "Shellwise", bundleID: "com.example.shellwise", bundlePath: "/Applications/Shellwise.app")
    static let finder = AppFacts(pid: 401, name: "Finder", bundleID: "com.apple.finder", bundlePath: "/System/Library/CoreServices/Finder.app")
    static let dock = AppFacts(pid: 402, name: "Dock", bundleID: "com.apple.dock", bundlePath: "/System/Library/CoreServices/Dock.app")
    static let installerApp = AppFacts(pid: 950, name: "Brushwork Installer", bundleID: "com.example.brushwork.installer", bundlePath: "/Volumes/Brushwork/Brushwork Installer.app")

    static var apps: [Int32: AppFacts] {
        Dictionary(uniqueKeysWithValues: [darkroom, shellwise, finder, dock, installerApp].map { ($0.pid, $0) })
    }

    static func process(_ pid: Int32, _ name: String, parent: Int32 = 1, executable: String? = nil) -> ProcessFacts {
        ProcessFacts(pid: pid, parent: parent, name: name, executable: executable ?? "/Applications/\(name).app/Contents/MacOS/\(name)")
    }

    static func use(_ process: ProcessFacts, _ files: [(String, OpenFile.Use)]) -> ProcessUse {
        ProcessUse(process: process, files: files.map { OpenFile(path: $0.0, use: $0.1) })
    }

    // The processes from the README's screenshots: a photo editor with raw files open, its
    // renderer, a shell in a terminal, Spotlight, and a command run from the terminal.
    static let darkroomProcess = process(812, "Darkroom")
    static let renderer = process(813, "Darkroom Renderer", parent: 812, executable: "/Applications/Darkroom.app/Contents/Frameworks/Darkroom Renderer.app/Contents/MacOS/Darkroom Renderer")
    static let zsh = process(901, "zsh", parent: 900, executable: "/bin/zsh")
    static let login = process(900, "login", parent: 700, executable: "/usr/bin/login")
    static let rsync = process(902, "rsync", parent: 901, executable: "/opt/homebrew/bin/rsync")
    static let mdworker = process(55, "mdworker_shared", executable: "/System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Versions/A/Support/mdworker_shared")

    static var table: [Int32: ProcessFacts] {
        Dictionary(uniqueKeysWithValues: [darkroomProcess, renderer, zsh, login, rsync, mdworker].map { ($0.pid, $0) })
    }
}
