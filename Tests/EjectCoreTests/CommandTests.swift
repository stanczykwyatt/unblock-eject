import Foundation
import Testing
@testable import EjectCore

@Suite("Command line tool")
struct CommandTests {
    @Test func parsing() throws {
        #expect(try Command.parse([]) == .check(path: nil, json: false, includeHidden: false))
        #expect(try Command.parse(["/Volumes/Travel SSD", "--json"]) == .check(path: "/Volumes/Travel SSD", json: true, includeHidden: false))
        #expect(try Command.parse(["--all"]) == .check(path: nil, json: false, includeHidden: true))
        #expect(try Command.parse(["--help", "--bogus"]) == .help)
        #expect(try Command.parse(["-h"]) == .help)
        #expect(try Command.parse(["--version"]) == .version)
        #expect(throws: Command.ParseError.message("Unknown option --force. See unblock-eject --help.")) { try Command.parse(["--force"]) }
        #expect(throws: Command.ParseError.self) { try Command.parse(["a", "b"]) }
    }

    private struct Run {
        var status: Int32 = 0
        var out = ""
        var err = ""
    }

    private func run(_ arguments: [String], volumes: [Volume] = [Sample.travel, Sample.card, Sample.hidden], uses: [ProcessUse] = []) -> Run {
        var result = Run()
        result.status = Command.run(
            arguments, workingDirectory: URL(fileURLWithPath: "/Volumes/Travel SSD/Photos"),
            volumes: FakeVolumes(all: volumes),
            scanner: DiskScanner(processes: FakeProcesses(uses: uses, table: Sample.table), ownPID: nil),
            apps: { Sample.apps }, out: { result.out += $0 }, err: { result.err += $0 }
        )
        return result
    }

    let busy = [
        Sample.use(Sample.darkroomProcess, [("/Volumes/Travel SSD/Photos/beach.raw", .file)]),
        Sample.use(Sample.zsh, [("/Volumes/Travel SSD/Projects", .folder)]),
    ]

    @Test func listsEveryDiskAndWhatsUsingIt() {
        let result = run([], uses: busy)
        #expect(result.status == 1)
        #expect(result.out == """
            Travel SSD · External drive · 1 TB · /Volumes/Travel SSD
              • Darkroom (pid 812): 1 file open
                  Photos/beach.raw
                Quit Darkroom to free the disk. It asks to save anything unsaved first, as usual.
              • zsh in Shellwise (pid 901): Working in Projects
                  Projects (working folder)
                A zsh shell in Shellwise is working in a folder on it. Type cd and press Return in that window, or close it.

            FIELD REC · Memory card · 64 GB · /Volumes/FIELD REC
              Nothing is using it. Free to eject.
            """)
    }

    @Test func freeDisksExitZero() {
        let result = run([])
        #expect(result.status == 0)
        #expect(!result.out.contains("Scratch"))
        #expect(run(["--all"]).out.contains("Scratch · Disk image"))
    }

    @Test func noDisks() {
        let result = run([], volumes: [])
        #expect(result.status == 0 && result.out.hasPrefix("No disks to eject."))
    }

    @Test func onePathPicksItsDisk() {
        // Relative to the working folder, which is on Travel SSD.
        let result = run(["."], uses: busy)
        #expect(result.status == 1)
        #expect(result.out.hasPrefix("Travel SSD") && !result.out.contains("FIELD REC"))
        #expect(run(["/Volumes/FIELD REC/"], uses: busy).status == 0)
        // A path on a hidden volume finds it without --all.
        #expect(run(["/private/tmp/scratch/x"]).out.hasPrefix("Scratch"))
    }

    @Test func aPathNotOnAnyDiskIsAnError() {
        let result = run(["/Users"])
        #expect(result.status == 2 && result.out.isEmpty)
        #expect(result.err == "/Users isn't on a disk you can eject. See the list with: unblock-eject")
    }

    @Test func longFileListsAreCut() {
        let many = (1...14).map { ("/Volumes/Travel SSD/f\($0).raw", OpenFile.Use.file) }
        let result = run([], uses: [Sample.use(Sample.darkroomProcess, many)])
        #expect(result.out.contains("…and 4 more"))
        #expect(!result.out.contains("f14.raw"))
    }

    @Test func json() throws {
        let result = run(["--json"], uses: busy)
        #expect(result.status == 1)
        let drives = try #require(try JSONSerialization.jsonObject(with: Data(result.out.utf8)) as? [[String: Any]])
        #expect(drives.count == 2)
        #expect(drives[0]["name"] as? String == "Travel SSD")
        #expect(drives[0]["kind"] as? String == "externalDrive")
        #expect(drives[0]["free"] as? Bool == false)
        let blockers = try #require(drives[0]["blockers"] as? [[String: Any]])
        #expect(blockers.map { $0["title"] as? String } == ["Darkroom", "zsh in Shellwise"])
        #expect(blockers.map { $0["canQuit"] as? Bool } == [true, false])
        #expect(blockers.map { $0["kind"] as? String } == ["app", "shell"])
        let files = try #require(blockers[0]["files"] as? [[String: String]])
        #expect(files == [["path": "/Volumes/Travel SSD/Photos/beach.raw", "use": "file"]])
        #expect(drives[1]["free"] as? Bool == true)
    }

    @Test func namesInJSONAreMadeSafeToo() throws {
        let sneaky = ProcessFacts(pid: 999, parent: 1, name: "evil\u{202E}txt.exe", executable: "/opt/evil\u{1B}[2J")
        let result = run(["--json"], uses: [Sample.use(sneaky, [("/Volumes/Travel SSD/a\u{202E}b", .file)])])
        #expect(!result.out.contains("\u{202E}") && !result.out.contains("\u{1B}"))
        #expect(result.out.contains("evil\u{FFFD}txt.exe"))
    }

    @Test func hiddenVolumesOnAListedDiskAreChecked() {
        let snapshot = Volume(path: "/Volumes/.hidden", name: "Hidden", device: "disk6s2", wholeDisk: "disk6", kind: .externalDrive, isHidden: true)
        let result = run([], volumes: [Sample.travel, snapshot], uses: [Sample.use(Sample.darkroomProcess, [("/Volumes/.hidden/x", .file)])])
        #expect(result.status == 1)
        #expect(result.out.hasPrefix("Travel SSD ·") && result.out.contains("Darkroom"))
    }

    @Test func theInnermostVolumeWinsForAPath() {
        let outer = Volume(path: "/Volumes/Outer", name: "Outer", device: "disk6s1", wholeDisk: "disk6", kind: .externalDrive)
        let inner = Volume(path: "/Volumes/Outer/Inner", name: "Inner", device: "disk7s1", wholeDisk: "disk7", kind: .memoryCard)
        #expect(run(["/Volumes/Outer/Inner/x"], volumes: [outer, inner]).out.hasPrefix("Inner"))
        #expect(run(["/Volumes/Outer/x"], volumes: [outer, inner]).out.hasPrefix("Outer"))
    }

    @Test func helpAndVersion() {
        #expect(run(["--help"]).out.contains("It only looks: nothing is quit or ejected."))
        #expect(run(["--version"]).out == "unblock-eject \(Command.toolVersion)")
        let bad = run(["--nope"])
        #expect(bad.status == 2 && bad.err.contains("Unknown option --nope"))
    }

    @Test func kindNames() {
        #expect(Command.kindName(.system(.timeMachine)) == "system:timeMachine")
        #expect(Command.kindName(.command(in: "X")) == "command")
        #expect(Command.kindName(.finder) == "finder")
        #expect(Command.kindName(.itself) == "itself")
        #expect(Command.kindName(.background(partOf: nil)) == "background")
    }
}
