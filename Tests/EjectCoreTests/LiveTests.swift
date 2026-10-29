import Darwin
import Foundation
import Testing
@testable import EjectCore

/// The real readers, pointed only at this test process and a throwaway folder.
@Suite("Reading from macOS")
struct LiveTests {
    @Test func findsAFileThisProcessHasOpen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EjectCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("held.txt")
        try Data("held".utf8).write(to: file)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        // The kernel reports the real path, with /private in front of /var.
        let real = Command.realPath(folder.path)
        let files = LiveProcesses.files(of: getpid(), under: [real])
        #expect(files == [OpenFile(path: real + "/held.txt", use: .file)])
        #expect(LiveProcesses.files(of: getpid(), under: [real + "-other"]).isEmpty)
    }

    @Test func filesOpenedOnlyToWatchArentBlockers() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EjectCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // The way the Dock and file watchers open a folder: it doesn't stop an eject.
        let watcher = open(folder.path, O_EVTONLY)
        #expect(watcher >= 0)
        defer { close(watcher) }
        #expect(LiveProcesses.files(of: getpid(), under: [Command.realPath(folder.path)]).isEmpty)
    }

    @Test func findsThisProcessesProgram() throws {
        let program = try #require(LiveProcesses.executable(of: getpid()))
        let folder = (program as NSString).deletingLastPathComponent
        #expect(LiveProcesses.files(of: getpid(), under: [folder]).contains(OpenFile(path: program, use: .program)))
    }

    @Test func describesThisProcess() throws {
        let me = try #require(LiveProcesses().process(getpid()))
        #expect(me.pid == getpid() && me.parent == getppid())
        #expect(me.executable == LiveProcesses.executable(of: getpid()))
        #expect(!me.name.isEmpty)
        #expect(LiveProcesses().process(-5) == nil)
    }

    @Test func otherUsersProcessesAreHidden() {
        // launchd runs as root: macOS doesn't tell other users what it has open.
        #expect(LiveProcesses.openFiles(of: 1).isEmpty)
    }

    @Test func theMountTableHasTheStartupDiskButNeverListsIt() {
        let mounts = MountTable.mounts()
        #expect(mounts.contains { $0.path == "/" && $0.device != nil })
        let volumes = MountTable().volumes(includeHidden: true)
        #expect(!volumes.contains { $0.path == "/" || $0.path.hasPrefix("/System/Volumes") })
    }

    @Test func cStringsInFixedArrays() {
        var tuple: (CChar, CChar, CChar, CChar) = (104, 105, 0, 120)
        #expect(MountTable.string(tuple) == "hi")
        tuple = (104, 105, 106, 107)
        #expect(MountTable.string(tuple) == "hijk")
        #expect(LiveProcesses.string([104, 0, 105]) == "h")
    }
}
