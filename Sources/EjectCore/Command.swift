import Foundation

/// The `unblock-eject` command line tool: lists the disks you can eject and what's using each, for
/// a terminal or a script. It only looks: it never quits or ejects anything.
public enum Command: Equatable {
    case check(path: String?, json: Bool, includeHidden: Bool)
    case help
    case version

    public static let toolVersion = "0.1.0"

    public static let usage = """
        unblock-eject \(toolVersion): see what's keeping a disk from ejecting.

        Usage:
          unblock-eject              Every disk you can eject, and what's using each
          unblock-eject <path>       Just the disk that path is on, like "/Volumes/Travel SSD"

        Options:
          --json             Print it as JSON
          --all              Include volumes mounted hidden from Finder
          --help, --version

        It only looks: nothing is quit or ejected. Like lsof without sudo, it can't see processes
        that macOS runs as the system, such as Spotlight's indexer and Time Machine.

        Exit status: 0 when nothing is using the disks listed, 1 when something is, 2 on errors.
        """

    public enum ParseError: Error, Equatable {
        case message(String)
    }

    public static func parse(_ arguments: [String]) throws -> Command {
        var path: String?
        var flags = Set<String>()
        for argument in arguments {
            if argument == "-h" {
                flags.insert("--help")
            } else if argument.hasPrefix("--") {
                flags.insert(argument)
            } else if path == nil {
                path = argument
            } else {
                throw ParseError.message("Give one path at most. See unblock-eject --help.")
            }
        }
        if flags.contains("--help") { return .help }
        if flags.contains("--version") { return .version }
        if let unknown = flags.subtracting(["--json", "--all"]).sorted().first {
            throw ParseError.message("Unknown option \(Describe.safe(unknown, limit: 60)). See unblock-eject --help.")
        }
        return .check(path: path, json: flags.contains("--json"), includeHidden: flags.contains("--all"))
    }

    /// Runs the tool and returns its exit status.
    public static func run(
        _ arguments: [String], workingDirectory: URL, volumes: any VolumeSource = MountTable(), scanner: DiskScanner = DiskScanner(),
        apps: () -> [Int32: AppFacts], out: (String) -> Void, err: (String) -> Void
    ) -> Int32 {
        let command: Command
        do {
            command = try parse(arguments)
        } catch ParseError.message(let message) {
            err(message)
            return 2
        } catch {
            err("\(error)")
            return 2
        }
        switch command {
        case .help:
            out(usage)
            return 0
        case .version:
            out("unblock-eject \(toolVersion)")
            return 0
        case .check(let path, let json, let includeHidden):
            // Hidden volumes are always checked, since ejecting a disk takes them too, but a disk
            // with only hidden volumes is listed only when asked for.
            var drives = Drive.group(volumes.volumes(includeHidden: true))
            if let path {
                let target = realPath(URL(fileURLWithPath: path, relativeTo: workingDirectory).standardizedFileURL.path)
                // The innermost volume wins, in case one is mounted inside another.
                let match = drives.compactMap { drive in drive.volume(containing: target).map { (drive, $0.path.count) } }.max { $0.1 < $1.1 }
                guard let drive = match?.0 else {
                    err("\(Describe.safe(target)) isn't on a disk you can eject. See the list with: unblock-eject")
                    return 2
                }
                drives = [drive]
            } else if !includeHidden {
                drives = drives.filter(\.isShown)
            }
            let running = apps()
            let reports = drives.map { scanner.report($0, apps: running) }
            out(json ? Self.json(reports) : text(reports))
            return reports.allSatisfy(\.isFree) ? 0 : 1
        }
    }

    /// Follows links the way the kernel does. Foundation's own version turns `/private/tmp` into
    /// `/tmp`, which isn't where anything is mounted.
    static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    // MARK: Output

    static let fileLimit = 10

    public static func text(_ reports: [DriveReport]) -> String {
        guard !reports.isEmpty else {
            return "No disks to eject. External drives, memory cards and disk images show up here once they're mounted."
        }
        var lines: [String] = []
        for report in reports {
            let drive = report.drive
            if !lines.isEmpty { lines.append("") }
            let places = drive.volumes.map { Describe.safe($0.path) }.joined(separator: ", ")
            lines.append("\(Describe.safe(drive.name)) · \(Describe.details(drive)) · \(places)")
            if report.isFree {
                lines.append("  Nothing is using it. Free to eject.")
                continue
            }
            for blocker in report.blockers {
                let pids = blocker.processes.map { String($0.pid) }.joined(separator: ", ")
                lines.append("  • \(Describe.title(blocker)) (pid \(pids)): \(Describe.summary(blocker, on: drive))")
                for file in blocker.files.prefix(fileLimit) {
                    lines.append("      \(Describe.file(file, on: drive))")
                }
                if blocker.files.count > fileLimit {
                    lines.append("      …and \(Describe.count(blocker.files.count - fileLimit, "more", plural: "more"))")
                }
                lines.append("    \(Describe.advice(blocker, on: drive))")
            }
        }
        return lines.joined(separator: "\n")
    }

    struct JSONDrive: Encodable {
        struct JSONVolume: Encodable {
            let name, path, device: String
        }
        struct JSONBlocker: Encodable {
            struct JSONProcess: Encodable {
                let pid: Int32
                let name: String
                let executable: String?
            }
            let title, kind, advice: String
            let app: String?
            let bundleID: String?
            let canQuit: Bool
            let processes: [JSONProcess]
            let files: [OpenFile]
        }
        let name, kind, wholeDisk: String
        let volumes: [JSONVolume]
        let free: Bool
        let blockers: [JSONBlocker]
    }

    public static func json(_ reports: [DriveReport]) -> String {
        // Names and paths come from the disk and other apps, so they're made safe here too: JSON
        // escapes control characters, but not the marks that reorder text in a terminal.
        func clean(_ text: String) -> String { Describe.safe(text, limit: 4096) }
        let drives = reports.map { report in
            JSONDrive(
                name: clean(report.drive.name), kind: report.drive.kind.rawValue, wholeDisk: report.drive.wholeDisk,
                volumes: report.drive.volumes.map { .init(name: clean($0.name), path: clean($0.path), device: $0.device) },
                free: report.isFree,
                blockers: report.blockers.map { blocker in
                    JSONDrive.JSONBlocker(
                        title: Describe.title(blocker), kind: kindName(blocker.kind), advice: Describe.advice(blocker, on: report.drive),
                        app: blocker.app.map { clean($0.name) }, bundleID: blocker.app?.bundleID.map(clean), canQuit: blocker.appToQuit != nil,
                        processes: blocker.processes.map { .init(pid: $0.pid, name: clean($0.name), executable: $0.executable.map(clean)) },
                        files: blocker.files.map { OpenFile(path: clean($0.path), use: $0.use) }
                    )
                }
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(drives)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    static func kindName(_ kind: Blocker.Kind) -> String {
        switch kind {
        case .app: "app"
        case .shell: "shell"
        case .command: "command"
        case .system(let system): "system:\(system.rawValue)"
        case .finder: "finder"
        case .itself: "itself"
        case .background: "background"
        }
    }
}
