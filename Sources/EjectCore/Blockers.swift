import Foundation

/// Something keeping a disk from ejecting, named the way you'd look for it: an app, a shell in a
/// terminal, or a part of macOS. Several processes can make up one, like an app and its helpers.
public struct Blocker: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// An app, or one of its helpers. Quitting the app lets go of the disk.
        case app
        /// A shell whose working folder is on the disk, in a terminal app.
        case shell(in: String)
        /// A command running in a terminal or another app.
        case command(in: String)
        case system(SystemProcess)
        /// Finder, which is never offered to quit.
        case finder
        /// Unblock Eject itself, opened from the disk.
        case itself
        /// A background process that isn't an app, maybe part of one that isn't open.
        case background(partOf: String?)
    }

    public let id: String
    public let kind: Kind
    public let name: String
    /// The app it belongs to, for its icon, and for quitting when `kind` is `.app`.
    public let app: AppFacts?
    /// An app bundle to take the icon from when no app is running.
    public let iconPath: String?
    public let processes: [ProcessFacts]
    public let files: [OpenFile]

    public init(id: String, kind: Kind, name: String, app: AppFacts?, iconPath: String?, processes: [ProcessFacts], files: [OpenFile]) {
        self.id = id
        self.kind = kind
        self.name = name
        self.app = app
        self.iconPath = iconPath
        self.processes = processes
        self.files = files
    }

    /// The app to quit to free the disk, if quitting is the fix. Never part of macOS.
    public var appToQuit: AppFacts? {
        guard kind == .app, let app, app.bundlePath != nil, !app.isSystem else { return nil }
        return app
    }

    /// Processes in the group other than the app itself, like "Google Chrome Helper (Renderer)".
    public var helpers: [ProcessFacts] {
        processes.filter { $0.pid != app?.pid }
    }

    fileprivate var rank: Int {
        switch kind {
        case .app: 0
        case .shell, .command: 1
        case .finder: 2
        case .system: 3
        case .background: 4
        case .itself: 5
        }
    }
}

public enum Blockers {
    /// Shells, which are only a problem for their working folder.
    static let shells: Set<String> = ["zsh", "bash", "sh", "fish", "tcsh", "csh", "ksh", "dash", "nu", "pwsh", "xonsh", "elvish"]

    /// Groups processes into the blockers you'd act on: each app with its helpers, each kind of
    /// shell or command per terminal app, and each part of macOS. Apps you can quit come first.
    public static func group(
        _ uses: [ProcessUse], apps: [Int32: AppFacts], ownPID: Int32? = nil, parent: (Int32) -> ProcessFacts? = { _ in nil }
    ) -> [Blocker] {
        var order: [String] = []
        var groups: [String: (kind: Blocker.Kind, name: String, app: AppFacts?, icon: String?, processes: [ProcessFacts], files: Set<OpenFile>)] = [:]
        let byBundle = Dictionary(apps.values.compactMap { app in app.bundlePath.map { ($0, app) } }, uniquingKeysWith: { a, b in a.pid < b.pid ? a : b })

        for use in uses {
            let owner = owner(of: use, apps: apps, byBundle: byBundle, ownPID: ownPID, parent: parent)
            if groups[owner.key] == nil {
                order.append(owner.key)
                groups[owner.key] = (owner.kind, owner.name, owner.app, owner.icon, [], [])
            }
            groups[owner.key]!.processes.append(use.process)
            groups[owner.key]!.files.formUnion(use.files)
        }

        return order.map { key in
            let group = groups[key]!
            return Blocker(
                id: key, kind: group.kind, name: group.name, app: group.app, iconPath: group.icon ?? group.app?.bundlePath,
                processes: group.processes.sorted { $0.pid < $1.pid }, files: group.files.sorted()
            )
        }
        .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private struct Owner {
        let key: String
        let kind: Blocker.Kind
        let name: String
        var app: AppFacts?
        var icon: String?
    }

    private static func owner(
        of use: ProcessUse, apps: [Int32: AppFacts], byBundle: [String: AppFacts], ownPID: Int32?, parent: (Int32) -> ProcessFacts?
    ) -> Owner {
        let process = use.process
        if process.pid == ownPID {
            return Owner(key: "itself", kind: .itself, name: "Unblock Eject", app: apps[process.pid])
        }
        if let system = SystemProcess.identify(process) {
            return Owner(key: "system:\(system.rawValue)", kind: .system(system), name: system.name)
        }
        if let app = apps[process.pid] {
            return owner(for: app)
        }
        let bundle = process.executable.flatMap(outermostApp)
        let bundleApp = bundle.flatMap { byBundle[$0] }
        let host = hostApp(of: process, apps: apps, parent: parent)
        // A helper of a running app, started by macOS or by the app itself. A program that only
        // lives inside an app, like a compiler inside a developer tool run from a terminal, belongs
        // to the terminal instead: quitting the other app wouldn't stop it.
        if let bundleApp, host == nil || host?.pid == bundleApp.pid {
            return owner(for: bundleApp)
        }
        // A command started from a terminal, or by an app: named after the app it's running in.
        if let host {
            let onlyFolder = use.files.allSatisfy { $0.use == .folder }
            let kind: Blocker.Kind = onlyFolder && shells.contains(process.name) ? .shell(in: host.name) : .command(in: host.name)
            return Owner(key: "in:\(host.pid):\(process.name)", kind: kind, name: process.name, app: host)
        }
        let partOf = bundle.map(appName)
        return Owner(key: "process:\(process.name)", kind: .background(partOf: partOf), name: process.name, icon: bundle)
    }

    private static func owner(for app: AppFacts) -> Owner {
        if app.bundleID == "com.apple.finder" {
            return Owner(key: "finder", kind: .finder, name: app.name, app: app)
        }
        if app.isSystem {
            return Owner(key: "system:macOS:\(app.bundleID ?? app.name)", kind: .system(.macOS), name: app.name, app: app)
        }
        return Owner(key: "app:\(app.pid)", kind: .app, name: app.name, app: app)
    }

    /// The nearest app among a process's parents, like the terminal a shell was started in.
    static func hostApp(of process: ProcessFacts, apps: [Int32: AppFacts], parent: (Int32) -> ProcessFacts?) -> AppFacts? {
        var pid = process.parent
        var seen: Set<Int32> = [process.pid]
        // A ceiling, and a check for loops, since process IDs can be reused as this walks.
        for _ in 0..<16 {
            guard pid > 1, !seen.contains(pid) else { return nil }
            seen.insert(pid)
            if let app = apps[pid] { return app }
            guard let next = parent(pid) else { return nil }
            pid = next.parent
        }
        return nil
    }

    /// The app a program belongs to: `/Applications/Big.app/Contents/Frameworks/Helper.app/...`
    /// belongs to `/Applications/Big.app`.
    public static func outermostApp(_ path: String) -> String? {
        var components: [Substring] = []
        for component in path.split(separator: "/") {
            components.append(component)
            if component.lowercased().hasSuffix(".app") { return "/" + components.joined(separator: "/") }
        }
        return nil
    }

    static func appName(_ bundlePath: String) -> String {
        ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}

/// What's keeping one disk from ejecting, as of one look.
public struct DriveReport: Hashable, Sendable, Identifiable {
    public let drive: Drive
    public let blockers: [Blocker]

    public var id: String { drive.id }
    public var isFree: Bool { blockers.isEmpty }

    public init(drive: Drive, blockers: [Blocker]) {
        self.drive = drive
        self.blockers = blockers
    }
}

/// Puts the pieces together: the processes using a disk, grouped and named.
public struct DiskScanner: Sendable {
    public let processes: any ProcessSource
    public let ownPID: Int32?

    public init(processes: any ProcessSource = LiveProcesses(), ownPID: Int32? = getpid()) {
        self.processes = processes
        self.ownPID = ownPID
    }

    public func report(_ drive: Drive, apps: [Int32: AppFacts]) -> DriveReport {
        let uses = processes.uses(of: drive.mountPoints)
        let blockers = Blockers.group(uses, apps: apps, ownPID: ownPID, parent: { processes.process($0) })
        return DriveReport(drive: drive, blockers: blockers)
    }
}
