import Foundation
import Testing
@testable import EjectCore

@Suite("Wording")
struct DescribeTests {
    let ssd = "/Volumes/Travel SSD"
    let drive = Sample.travelDrive

    private func blocker(_ kind: Blocker.Kind, name: String = "Darkroom", app: AppFacts? = Sample.darkroom, files: [(String, OpenFile.Use)] = [], processes: [ProcessFacts] = [Sample.darkroomProcess]) -> Blocker {
        Blocker(id: "x", kind: kind, name: name, app: app, iconPath: nil, processes: processes, files: files.map { OpenFile(path: $0.0, use: $0.1) })
    }

    @Test func counts() {
        #expect(Describe.count(1, "file") == "1 file")
        #expect(Describe.count(3, "file") == "3 files")
        #expect(Describe.count(2, "more", plural: "more") == "2 more")
        #expect(Describe.list([]) == "")
        #expect(Describe.list(["A"]) == "A")
        #expect(Describe.list(["A", "B"]) == "A and B")
        #expect(Describe.list(["A", "B", "C"]) == "A, B and C")
    }

    @Test func namesFromTheDiskAreMadeSafe() {
        // An escape sequence that would recolor a terminal, and a right-to-left mark disguising "exe.txt".
        #expect(Describe.safe("photo\u{1B}[31m.raw") == "photo\u{FFFD}[31m.raw")
        #expect(Describe.safe("invoice\u{202E}txt.exe") == "invoice\u{FFFD}txt.exe")
        #expect(Describe.safe("two\nlines\u{2028}here\u{200B}") == "two\u{FFFD}lines\u{FFFD}here\u{FFFD}")
        // Emoji that need joiners stay whole.
        #expect(Describe.safe("👩‍💻 notes.txt") == "👩‍💻 notes.txt")
        // Other invisible marks: a function application, a soft hyphen, a tag letter, a blank letter.
        #expect(Describe.safe("a\u{2061}b\u{00AD}c\u{E0041}d\u{3164}e\u{7F}\u{9B}") == "a\u{FFFD}b\u{FFFD}c\u{FFFD}d\u{FFFD}e\u{FFFD}\u{FFFD}")
        // One letter with thousands of accents is still cut short.
        #expect(Describe.safe("a" + String(repeating: "\u{0301}", count: 5000), limit: 10).unicodeScalars.count < 100)
        #expect(Describe.safe(String(repeating: "a", count: 400)).count == 300)
        #expect(Describe.safe(String(repeating: "a", count: 400), limit: 10) == "aaaaaaaaa…")
    }

    @Test func driveDetails() {
        #expect(Describe.details(drive) == "External drive · 1 TB")
        #expect(Describe.details(Drive(wholeDisk: "disk9", volumes: [Sample.hidden])) == "Disk image")
        #expect(Describe.kind(.memoryCard) == "Memory card")
        #expect(Describe.size(0) == nil && Describe.size(nil) == nil)
    }

    @Test func pathsAreShownFromTheTopOfTheDisk() {
        #expect(Describe.path(ssd + "/Photos/beach.raw", on: drive) == "Photos/beach.raw")
        #expect(Describe.path(ssd, on: drive) == "the top of Travel SSD")
        #expect(Describe.path("/Volumes/Archive 2/x/y", on: Sample.archiveDrive) == "Archive 2/x/y")
        #expect(Describe.path("/Volumes/Archive", on: Sample.archiveDrive) == "Archive")
        #expect(Describe.path("/elsewhere/z", on: drive) == "/elsewhere/z")
        #expect(Describe.file(OpenFile(path: ssd + "/Projects", use: .folder), on: drive) == "Projects (working folder)")
        #expect(Describe.file(OpenFile(path: ssd + "/Tool.app/Contents/MacOS/Tool", use: .program), on: drive) == "Tool.app/Contents/MacOS/Tool (running from this disk)")
        #expect(Describe.file(OpenFile(path: ssd + "/Plugins/x.bundle", use: .loaded), on: drive) == "Plugins/x.bundle (loaded)")
        #expect(Describe.file(OpenFile(path: ssd, use: .unnamed), on: drive).hasPrefix("something on Travel SSD macOS doesn't give a name for"))
    }

    @Test func titles() {
        #expect(Describe.title(blocker(.app)) == "Darkroom")
        #expect(Describe.title(blocker(.shell(in: "Shellwise"), name: "zsh")) == "zsh in Shellwise")
        #expect(Describe.title(blocker(.command(in: "Shellwise"), name: "rsync")) == "rsync in Shellwise")
        #expect(Describe.title(blocker(.system(.spotlight), name: "Spotlight")) == "Spotlight")
    }

    @Test func summaries() {
        #expect(Describe.summary(blocker(.app, files: [(ssd + "/a", .file), (ssd + "/b", .file)]), on: drive) == "2 files open")
        #expect(Describe.summary(blocker(.app, files: [(ssd + "/A.app/Contents/MacOS/A", .program), (ssd + "/x", .file)]), on: drive) == "Running from this disk · 1 file open")
        #expect(Describe.summary(blocker(.shell(in: "Shellwise"), files: [(ssd + "/Projects", .folder)]), on: drive) == "Working in Projects")
        #expect(Describe.summary(blocker(.app, files: [(ssd + "/x.bundle", .loaded)]), on: drive) == "Has a file from it loaded")
        #expect(Describe.summary(blocker(.app, files: [(ssd, .unnamed)]), on: drive) == "Has something open on it")
        let helpers = blocker(.app, files: [(ssd + "/a", .file)], processes: [Sample.darkroomProcess, Sample.renderer])
        #expect(Describe.summary(helpers, on: drive) == "1 file open · through Darkroom Renderer")
        let many = blocker(.app, files: [(ssd + "/a", .file)], processes: [Sample.darkroomProcess] + (1...4).map { Sample.process(Int32(900 + $0), "Helper \($0)") })
        #expect(Describe.summary(many, on: drive) == "1 file open · through Helper 1, Helper 2 and 2 others")
    }

    @Test func adviceForEachKind() {
        #expect(Describe.advice(blocker(.app), on: drive).hasPrefix("Quit Darkroom to free the disk."))
        #expect(Describe.advice(blocker(.app, app: Sample.dock), on: drive) == "Part of macOS. It usually lets go in a moment.")
        #expect(Describe.advice(blocker(.shell(in: "Shellwise"), name: "zsh"), on: drive).contains("Type cd and press Return"))
        #expect(Describe.advice(blocker(.command(in: "Shellwise"), name: "rsync"), on: drive) == "rsync is running in Shellwise. Stop it there, or let it finish.")
        #expect(Describe.advice(blocker(.finder, name: "Finder"), on: drive).hasPrefix("Finder is copying"))
        #expect(Describe.advice(blocker(.itself), on: drive).contains("Applications folder"))
        #expect(Describe.advice(blocker(.background(partOf: "CloudSync"), name: "SyncAgent"), on: drive).hasPrefix("Part of CloudSync"))
        #expect(Describe.advice(blocker(.background(partOf: nil), name: "x"), on: drive).hasPrefix("A background process."))
        for system in SystemProcess.allCases {
            let text = Describe.advice(blocker(.system(system), name: system.name), on: drive)
            #expect(!text.isEmpty && text.hasSuffix("."))
        }
        #expect(Describe.advice(blocker(.system(.spotlight)), on: drive).contains("Search Privacy"))
        #expect(Describe.advice(blocker(.system(.diskImage), files: [(ssd + "/Installers/Tool.dmg", .file)]), on: drive) == "Tool.dmg is still open as a disk. Eject that first.")
        #expect(Describe.advice(blocker(.system(.diskImage)), on: drive) == "A disk image stored on it is still open as a disk. Eject that first.")
    }

    @Test func statusLines() {
        #expect(Describe.status(DriveReport(drive: drive, blockers: [])) == "Nothing is using it")
        let two = [blocker(.app), blocker(.shell(in: "Shellwise"), name: "zsh")]
        #expect(Describe.status(DriveReport(drive: drive, blockers: two)) == "In use by Darkroom and zsh in Shellwise")
        let five = (1...5).map { blocker(.app, name: "App \($0)") }
        #expect(Describe.status(DriveReport(drive: drive, blockers: five)) == "In use by App 1, App 2 and 3 others")
    }

    @Test func ejectMessages() {
        let one = [blocker(.app)]
        #expect(Describe.eject(.ejected, drive: drive, blockers: []) == "Ejected “Travel SSD”. It's safe to unplug.")
        #expect(Describe.eject(.ejected, drive: Drive(wholeDisk: "disk8", volumes: [Sample.installer]), blockers: []) == "Ejected “Brushwork”.")
        #expect(Describe.eject(.busy(message: nil), drive: drive, blockers: one) == "Couldn't eject “Travel SSD”: Darkroom still has files open on it.")
        let many = (1...4).map { blocker(.app, name: "App \($0)") }
        #expect(Describe.eject(.busy(message: nil), drive: drive, blockers: many) == "Couldn't eject “Travel SSD”: App 1, App 2 and App 3 and others still have files open on it.")
        #expect(Describe.eject(.busy(message: nil), drive: drive, blockers: []).contains("something macOS runs"))
        #expect(Describe.eject(.busy(message: "Backup in progress"), drive: drive, blockers: []).hasSuffix("macOS said: “Backup in progress”"))
        #expect(Describe.eject(.notAllowed, drive: drive, blockers: []).hasPrefix("macOS didn't allow"))
        #expect(Describe.eject(.gone, drive: drive, blockers: []) == "“Travel SSD” was already ejected.")
        #expect(Describe.eject(.timedOut, drive: drive, blockers: []).hasPrefix("macOS didn't finish ejecting"))
        #expect(Describe.eject(.failed(code: -119930879), drive: drive, blockers: []) == "Couldn't eject “Travel SSD” (error 0xF8DA0001).")
    }

    @Test func relativeTimes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(Describe.relative(now.addingTimeInterval(-3), now: now) == "just now")
        #expect(Describe.relative(now.addingTimeInterval(-42), now: now) == "42 s ago")
        #expect(Describe.relative(now.addingTimeInterval(-600), now: now) == "10 min ago")
        #expect(Describe.relative(now.addingTimeInterval(-7300), now: now) == "2 h ago")
        #expect(Describe.relative(now.addingTimeInterval(60), now: now) == "just now")
    }
}

@Suite("Eject results")
struct EjectResultTests {
    @Test func statusCodes() {
        #expect(EjectResult.from(status: 0) == .ejected)
        #expect(EjectResult.from(status: Int32(bitPattern: 0xF8DA0002), message: "x") == .busy(message: "x"))
        #expect(EjectResult.from(status: Int32(bitPattern: 0xF8DA0004)) == .busy(message: nil))
        #expect(EjectResult.from(status: Int32(bitPattern: 0xF8DA0008)) == .notAllowed)
        #expect(EjectResult.from(status: Int32(bitPattern: 0xF8DA0009)) == .notAllowed)
        #expect(EjectResult.from(status: Int32(bitPattern: 0xF8DA0006)) == .gone)
        #expect(EjectResult.from(status: Int32(bitPattern: 0xF8DA0007)) == .gone)
        // Unmount's own errors, wrapped in Disk Arbitration's Unix range: EBUSY is what a busy
        // disk image really returned on macOS 15.
        #expect(EjectResult.from(status: 0xC010) == .busy(message: nil))
        #expect(EjectResult.from(status: 0xC001) == .notAllowed)
        #expect(EjectResult.from(status: 0xC00D) == .notAllowed)
        #expect(EjectResult.from(status: 0xC002) == .gone)
        #expect(EjectResult.from(status: 0xC016) == .failed(code: 0xC016))
        #expect(EjectResult.from(status: 0xC05C) == .failed(code: 0xC05C))
        #expect(EjectResult.from(status: Int32(bitPattern: 0xF8DA0001)) == .failed(code: Int32(bitPattern: 0xF8DA0001)))
    }
}
