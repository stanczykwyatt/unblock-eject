import Foundation
import Testing
@testable import EjectCore

/// The whole job on a real disk: a scratch disk image made for the test, mounted hidden so Finder
/// never shows it, with files held open by processes the test starts. Nothing else is touched, and
/// only that image is ever ejected. It takes a few seconds, so it only runs when asked:
///
///   UNBLOCK_EJECT_DISK_TESTS=1 swift test --filter "Disk image"
@Suite("Disk image", .enabled(if: ProcessInfo.processInfo.environment["UNBLOCK_EJECT_DISK_TESTS"] == "1"), .serialized)
struct DiskImageTests {
    final class Scratch {
        let folder: URL
        let image: URL
        let mountPoint: String
        var helpers: [Process] = []

        init() throws {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("UnblockEjectDisk-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            image = folder.appendingPathComponent("scratch.dmg")
            mountPoint = Command.realPath(folder.path) + "/mount"
            try Self.run("/usr/bin/hdiutil", ["create", "-size", "16m", "-fs", "APFS", "-volname", "Unblock Scratch", "-quiet", image.path])
            try FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)
            try Self.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-noautoopen", "-mountpoint", mountPoint, "-quiet", image.path])
        }

        /// Starts a process the test owns, which holds something open on the image until stopped.
        func hold(_ script: String) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", script]
            try process.run()
            helpers.append(process)
        }

        func stopHelpers() {
            for helper in helpers where helper.isRunning {
                helper.terminate()
                helper.waitUntilExit()
            }
            helpers = []
        }

        /// Whether the image is still attached as a device, mounted or not.
        var isAttached: Bool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["info"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            return output.contains(folder.lastPathComponent)
        }

        var isMounted: Bool {
            MountTable.mounts().contains { $0.path == mountPoint }
        }

        /// Detaches the image if a test left it attached, then removes the folder.
        func cleanUp() {
            stopHelpers()
            if isMounted { try? Self.run("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet"]) }
            try? FileManager.default.removeItem(at: folder)
        }

        static func run(_ tool: String, _ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        }
    }

    /// Waits for helpers to get going, checking rather than sleeping a fixed time.
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<50 where !condition() {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    @Test func findsWhatsHoldingTheImageAndEjectsItOnceFree() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let volume = try #require(MountTable().volumes(includeHidden: true).first { $0.path == scratch.mountPoint })
        #expect(volume.kind == .diskImage && volume.name == "Unblock Scratch" && volume.isHidden)
        // APFS: the volume is in a container that sits on the image's own disk.
        #expect(volume.container != volume.wholeDisk)
        #expect(volume.device.hasPrefix(volume.container + "s"))
        #expect(!MountTable().volumes(includeHidden: false).contains { $0.path == scratch.mountPoint })
        let drive = try #require(Drive.group([volume]).first)

        let scanner = DiskScanner()
        #expect(scanner.report(drive, apps: [:]).isFree)

        try FileManager.default.createDirectory(atPath: scratch.mountPoint + "/Projects", withIntermediateDirectories: true)
        try Data("raw".utf8).write(to: URL(fileURLWithPath: scratch.mountPoint + "/beach.raw"))
        try scratch.hold("exec 3<'\(scratch.mountPoint)/beach.raw'; exec sleep 60")
        try scratch.hold("cd '\(scratch.mountPoint)/Projects' && exec sleep 61")
        // A file deleted while it's open still holds the disk, with no path to show.
        try Data("tmp".utf8).write(to: URL(fileURLWithPath: scratch.mountPoint + "/scratch.tmp"))
        try scratch.hold("exec 4<'\(scratch.mountPoint)/scratch.tmp'; rm '\(scratch.mountPoint)/scratch.tmp'; exec sleep 62")
        await until { scanner.report(drive, apps: [:]).blockers.flatMap(\.processes).count >= 3 }

        let report = scanner.report(drive, apps: [:])
        let files = report.blockers.flatMap(\.files)
        #expect(files.contains(OpenFile(path: scratch.mountPoint + "/beach.raw", use: .file)))
        #expect(files.contains(OpenFile(path: scratch.mountPoint + "/Projects", use: .folder)))
        #expect(report.blockers.flatMap(\.processes).allSatisfy { $0.name == "sleep" })
        #expect(report.blockers.flatMap(\.processes).count == 3)
        #expect(Set(report.blockers.flatMap(\.processes).map(\.pid)) == Set(scratch.helpers.map(\.processIdentifier)))
        #expect(report.blockers.allSatisfy { $0.appToQuit == nil })

        // Busy: macOS refuses, and nothing changes.
        let refused = await DiskEjector().eject(drive)
        guard case .busy = refused else {
            Issue.record("Expected busy, got \(refused)")
            return
        }
        #expect(scratch.isMounted)

        // A disk that isn't the one listed anymore is never ejected in its place.
        let stale = Volume(path: scratch.mountPoint + "-elsewhere", name: volume.name, device: volume.device, wholeDisk: volume.wholeDisk,
                           container: volume.container, kind: volume.kind, uuid: volume.uuid)
        #expect(await DiskEjector().eject(Drive(wholeDisk: drive.wholeDisk, volumes: [stale])) == .gone)
        let otherID = Volume(path: volume.path, name: volume.name, device: volume.device, wholeDisk: volume.wholeDisk,
                             container: volume.container, kind: volume.kind, uuid: "00000000-0000-0000-0000-000000000000")
        #expect(await DiskEjector().eject(Drive(wholeDisk: drive.wholeDisk, volumes: [otherID])) == .gone)
        #expect(volume.uuid != nil)
        #expect(scratch.isMounted)

        scratch.stopHelpers()
        await until { scanner.report(drive, apps: [:]).isFree }
        #expect(scanner.report(drive, apps: [:]).isFree)
        #expect(await DiskEjector().eject(drive) == .ejected)
        #expect(!scratch.isMounted)
        // Ejected for real, as Finder does: the image is detached, not just unmounted.
        #expect(!scratch.isAttached)
        let again = await DiskEjector().eject(drive)
        #expect(again == .gone, "Got \(again)")
    }

    @Test func theCommandLineToolFindsItByPath() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        var out = ""
        var status = Command.run([scratch.mountPoint], workingDirectory: scratch.folder, apps: { [:] }, out: { out += $0 }, err: { _ in })
        #expect(status == 0 && out.contains("Unblock Scratch · Disk image") && out.contains("Free to eject"))
        out = ""
        status = Command.run([], workingDirectory: scratch.folder, apps: { [:] }, out: { out += $0 }, err: { _ in })
        #expect(!out.contains("Unblock Scratch"))
    }
}
