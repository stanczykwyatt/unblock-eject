import EjectCore
import Foundation
import Observation

/// What the menu and the window show: each disk you can eject, what's using it, and how the last
/// eject went. Nothing here quits or ejects on its own; only the buttons you click do.
@MainActor
@Observable
final class EjectModel {
    struct Message: Equatable {
        /// The disk it's about, exactly as listed, so a different disk given the same name later
        /// isn't mistaken for it.
        let drive: Drive
        let text: String
        let isProblem: Bool
        let date: Date
    }

    @ObservationIgnored let volumes: any VolumeSource
    @ObservationIgnored let scanner: DiskScanner
    @ObservationIgnored let ejector: any Ejecting
    @ObservationIgnored let control: any AppControl
    @ObservationIgnored var runningApps: () -> [Int32: AppFacts]
    @ObservationIgnored var now: () -> Date = Date.init

    private(set) var reports: [DriveReport] = []
    private(set) var lastCheck: Date?
    /// Disks being ejected right now, by ID.
    private(set) var ejecting: Set<String> = []
    /// Apps asked to quit, by process ID, with when. They may still be asking to save.
    private(set) var quitting: [Int32: Date] = [:]
    private(set) var message: Message?

    /// How long a "Quitting…" lasts if the app doesn't quit, as when you cancel its save dialog.
    static let quitPatience: TimeInterval = 20
    /// How long the last eject's outcome stays in the menu.
    static let messageLifetime: TimeInterval = 120

    init(
        volumes: any VolumeSource = MountTable(), scanner: DiskScanner = DiskScanner(), ejector: any Ejecting = DiskEjector(),
        control: any AppControl, runningApps: @escaping () -> [Int32: AppFacts]
    ) {
        self.volumes = volumes
        self.scanner = scanner
        self.ejector = ejector
        self.control = control
        self.runningApps = runningApps
    }

    /// Looks again: which disks are mounted and what has files open on them. It takes a few
    /// milliseconds and opens none of your files.
    func refresh() {
        let apps = runningApps()
        // Hidden volumes are checked with the disk they're on, since ejecting takes them too, but
        // a disk with only hidden volumes isn't listed.
        let drives = Drive.group(volumes.volumes(includeHidden: true)).filter(\.isShown)
        reports = drives.map { scanner.report($0, apps: apps) }
        let date = now()
        lastCheck = date
        quitting = quitting.filter { pid, asked in apps[pid] != nil && date.timeIntervalSince(asked) < Self.quitPatience }
        if let message, date.timeIntervalSince(message.date) > Self.messageLifetime {
            self.message = nil
        }
    }

    func report(_ id: String) -> DriveReport? {
        reports.first { $0.id == id }
    }

    func isQuitting(_ app: AppFacts) -> Bool {
        quitting[app.pid] != nil
    }

    /// Asks the blocker's app to quit, the normal way. Parts of macOS are never asked.
    func quit(_ blocker: Blocker) {
        guard let app = blocker.appToQuit, !isQuitting(app) else { return }
        if control.quit(app) {
            quitting[app.pid] = now()
        }
    }

    /// Ejects a disk, as Finder does, and says how it went. If something still has files open,
    /// macOS refuses and the disk stays as it was.
    @discardableResult
    func eject(_ drive: Drive) async -> EjectResult {
        guard !ejecting.contains(drive.id) else { return .busy(message: nil) }
        ejecting.insert(drive.id)
        let result = await ejector.eject(drive)
        ejecting.remove(drive.id)
        refresh()
        let blockers = reports.first { $0.drive.id == drive.id && $0.drive.volumes.map(\.path) == drive.volumes.map(\.path) }?.blockers ?? []
        message = Message(
            drive: drive, text: Describe.eject(result, drive: drive, blockers: blockers),
            isProblem: result != .ejected && result != .gone, date: now()
        )
        return result
    }

    /// Clears a problem once you've seen it, or once the disk is gone.
    func dismissMessage() {
        message = nil
    }

    /// Whether the menu bar icon should say something went wrong.
    var needsAttention: Bool {
        guard let message, message.isProblem else { return false }
        return reports.contains { $0.drive == message.drive }
    }
}
