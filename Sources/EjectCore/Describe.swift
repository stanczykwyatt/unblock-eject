import Foundation

/// All the wording, in one place so the menu, the window and the command line tool say the same thing.
public enum Describe {
    public static func count(_ number: Int, _ noun: String, plural: String? = nil) -> String {
        "\(number) \(number == 1 ? noun : plural ?? noun + "s")"
    }

    /// Joins names the way you'd say them: "A", "A and B", "A, B and C".
    public static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }

    /// Text from a disk or another app, made safe to show: file names can hold anything, including
    /// characters that would send a terminal an escape sequence or flip text right to left to
    /// disguise a name. Those are replaced, and very long names are shortened.
    public static func safe(_ text: String, limit: Int = 300) -> String {
        var result = ""
        var scalars = 0
        for scalar in text.unicodeScalars {
            // A ceiling on characters too, since one letter can carry thousands of accents.
            scalars += 1
            if scalars > limit * 4 { break }
            let category = scalar.properties.generalCategory
            if category == .control || category == .lineSeparator || category == .paragraphSeparator
                || (category == .format && !joiners.contains(scalar.value)) || blanks.contains(scalar.value) {
                result.unicodeScalars.append("\u{FFFD}")
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        if result.count > limit || scalars > limit * 4 {
            result = String(result.prefix(limit - 1)) + "…"
        }
        return result
    }

    /// Invisible marks that are kept: emoji and some scripts need the zero-width joiners.
    static let joiners: Set<UInt32> = [0x200C, 0x200D]
    /// Letters that draw as nothing at all, which could make a name look empty or like another.
    static let blanks: Set<UInt32> = [0x115F, 0x1160, 0x3164, 0xFFA0, 0x2800]

    public static func kind(_ kind: Volume.Kind) -> String {
        switch kind {
        case .externalDrive: "External drive"
        case .memoryCard: "Memory card"
        case .diskImage: "Disk image"
        }
    }

    public static func size(_ bytes: Int64?) -> String? {
        guard let bytes, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// "External drive · 1 TB"
    public static func details(_ drive: Drive) -> String {
        let total = drive.shownVolumes.compactMap(\.size).reduce(0, +)
        return [kind(drive.kind), size(total)].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Blockers

    /// How a blocker is named in a list: "Darkroom", "zsh in Terminal", "Spotlight".
    public static func title(_ blocker: Blocker) -> String {
        let name = safe(blocker.name, limit: 80)
        switch blocker.kind {
        case .shell(let app), .command(let app): return "\(name) in \(safe(app, limit: 80))"
        default: return name
        }
    }

    /// A path as seen from the top of the disk it's on: `Photos/beach.raw`.
    public static func path(_ path: String, on drive: Drive) -> String {
        guard let volume = drive.volume(containing: path) else { return safe(path) }
        var inside = String(path.dropFirst(volume.path.count))
        while inside.hasPrefix("/") { inside.removeFirst() }
        let prefix = drive.volumes.count > 1 ? volume.name + "/" : ""
        if inside.isEmpty { return safe(drive.volumes.count > 1 ? volume.name : "the top of \(volume.name)") }
        return safe(prefix + inside)
    }

    /// One thing a blocker has open, with how it's using it.
    public static func file(_ file: OpenFile, on drive: Drive) -> String {
        let shown = path(file.path, on: drive)
        switch file.use {
        case .program: return "\(shown) (running from this disk)"
        case .file: return shown
        case .folder: return "\(shown) (working folder)"
        case .loaded: return "\(shown) (loaded)"
        case .unnamed: return "something on \(safe(drive.volume(containing: file.path)?.name ?? drive.name, limit: 80)) macOS doesn't give a name for, like a file deleted while open"
        }
    }

    /// A short line under a blocker's name: what it has open.
    public static func summary(_ blocker: Blocker, on drive: Drive) -> String {
        let files = blocker.files
        let open = files.filter { $0.use == .file }.count
        var parts: [String] = []
        if files.contains(where: { $0.use == .program }) { parts.append("Running from this disk") }
        if open > 0 { parts.append(count(open, "file") + " open") }
        if let folder = files.first(where: { $0.use == .folder }) { parts.append("Working in " + path(folder.path, on: drive)) }
        if parts.isEmpty, files.contains(where: { $0.use == .loaded }) { parts.append("Has a file from it loaded") }
        if parts.isEmpty, files.contains(where: { $0.use == .unnamed }) { parts.append("Has something open on it") }
        if !blocker.helpers.isEmpty, blocker.kind == .app {
            let names = Array(Set(blocker.helpers.map { safe($0.name, limit: 60) })).sorted()
            parts.append("through " + list(names.count > 2 ? Array(names.prefix(2)) + [count(names.count - 2, "other")] : names))
        }
        return parts.joined(separator: " · ")
    }

    /// What to do about a blocker, in a sentence or two.
    public static func advice(_ blocker: Blocker, on drive: Drive) -> String {
        let name = safe(blocker.name, limit: 80)
        switch blocker.kind {
        case .app:
            if blocker.app?.isSystem == true { return "Part of macOS. It usually lets go in a moment." }
            if blocker.appToQuit == nil { return "Quit \(name) the way you usually would, or let it finish." }
            return "Quit \(name) to free the disk. It asks to save anything unsaved first, as usual."
        case .shell(let app):
            return "A \(name) shell in \(safe(app, limit: 80)) is working in a folder on it. Type cd and press Return in that window, or close it."
        case .command(let app):
            return "\(name) is running in \(safe(app, limit: 80)). Stop it there, or let it finish."
        case .finder:
            return "Finder is copying or previewing something on it. Let it finish, or close the Finder windows showing it."
        case .itself:
            return "This is Unblock Eject itself, opened from this disk. Move it to your Applications folder and open it from there."
        case .background(let app):
            if let app { return "Part of \(safe(app, limit: 80)), running in the background. It may let go in a moment; if not, quit \(safe(app, limit: 80)) or restart." }
            return "A background process. It may let go in a moment; if not, quit the app it belongs to or restart."
        case .system(let system):
            switch system {
            case .spotlight:
                return "Spotlight is indexing it, which usually takes a minute. To keep Spotlight off this disk, add it to Search Privacy in System Settings → Spotlight."
            case .timeMachine:
                return "Time Machine is backing up to it. Let the backup finish, or stop it in System Settings → General → Time Machine."
            case .quickLook:
                return "Quick Look is making a preview or thumbnail of a file on it. This usually takes a moment."
            case .photos:
                return "Photos is using a library on it. Quit Photos, then give it a moment."
            case .mediaLibrary:
                return "A Music or TV library is on it. Quit Music and TV, then give it a moment."
            case .diskImage:
                let images = blocker.files.filter { $0.use == .file }.map { ($0.path as NSString).lastPathComponent }
                let named = images.isEmpty ? "a disk image stored on it" : list(images.map { safe($0, limit: 80) })
                return "\(named.prefix(1).uppercased() + named.dropFirst()) is still open as a disk. Eject that first."
            case .securityCheck:
                return "macOS is checking an app on it for malware. This usually takes a moment."
            case .macOS:
                return "Part of macOS. It usually lets go in a moment."
            }
        }
    }

    // MARK: Drives

    /// "Free to eject", or who's using it: "In use by Darkroom and zsh in Terminal".
    public static func status(_ report: DriveReport) -> String {
        if report.isFree { return "Nothing is using it" }
        let titles = report.blockers.map(title)
        if titles.count > 3 {
            return "In use by " + titles.prefix(2).joined(separator: ", ") + " and " + count(titles.count - 2, "other")
        }
        return "In use by " + list(titles)
    }

    /// Said when nothing you can see is using a disk that still won't eject.
    public static let hiddenProcesses = "Parts of macOS that run as the system, like Spotlight's indexer and Time Machine, are hidden from apps. If it won't eject, give it a minute and try again."

    public static func eject(_ result: EjectResult, drive: Drive, blockers: [Blocker]) -> String {
        let name = "“\(safe(drive.name, limit: 80))”"
        switch result {
        case .ejected:
            return drive.kind == .diskImage ? "Ejected \(name)." : "Ejected \(name). It's safe to unplug."
        case .busy(let message):
            var text: String
            if blockers.isEmpty {
                text = "Couldn't eject \(name): something macOS runs is still using it, like Spotlight or Time Machine. Give it a minute and try again."
            } else {
                text = "Couldn't eject \(name): \(list(blockers.prefix(3).map(title)))\(blockers.count > 3 ? " and others" : "") still \(blockers.count == 1 ? "has" : "have") files open on it."
            }
            if let message, !message.isEmpty { text += " macOS said: “\(safe(message, limit: 160))”" }
            return text
        case .notAllowed:
            return "macOS didn't allow ejecting \(name). Try ejecting it in Finder."
        case .gone:
            return "\(name) was already ejected."
        case .timedOut:
            return "macOS didn't finish ejecting \(name). Check it in Finder, and try again."
        case .failed(let code):
            return "Couldn't eject \(name) (error \(String(format: "0x%08X", UInt32(bitPattern: code))))."
        }
    }

    /// "5 min ago", or "just now".
    public static func relative(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 10 { return "just now" }
        if seconds < 60 { return "\(Int(seconds)) s ago" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        return "\(Int(seconds / 3600)) h ago"
    }
}
