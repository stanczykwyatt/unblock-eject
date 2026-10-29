import Testing
@testable import EjectCore

@Suite("Blockers")
struct BlockerTests {
    let ssd = "/Volumes/Travel SSD"

    private func group(_ uses: [ProcessUse], apps: [Int32: AppFacts] = Sample.apps, ownPID: Int32? = 1234) -> [Blocker] {
        Blockers.group(uses, apps: apps, ownPID: ownPID, parent: { Sample.table[$0] })
    }

    @Test func anAppAndItsHelpersAreOneBlocker() throws {
        let blockers = group([
            Sample.use(Sample.darkroomProcess, [("\(ssd)/Photos/dunes.raw", .file), ("\(ssd)/Photos/beach.raw", .file)]),
            Sample.use(Sample.renderer, [("\(ssd)/Photos/beach.raw", .file), ("\(ssd)/Photos/cliffs.raw", .file)]),
        ])
        let darkroom = try #require(blockers.first)
        #expect(blockers.count == 1)
        #expect(darkroom.kind == .app && darkroom.name == "Darkroom")
        #expect(darkroom.appToQuit == Sample.darkroom)
        #expect(darkroom.processes.map(\.pid) == [812, 813])
        #expect(darkroom.helpers.map(\.name) == ["Darkroom Renderer"])
        // The same file open in both is listed once, sorted.
        #expect(darkroom.files.map(\.path) == ["\(ssd)/Photos/beach.raw", "\(ssd)/Photos/cliffs.raw", "\(ssd)/Photos/dunes.raw"])
        #expect(darkroom.iconPath == "/Applications/Darkroom.app")
    }

    @Test func aHelperAloneStillQuitsItsApp() throws {
        let blockers = group([Sample.use(Sample.renderer, [("\(ssd)/a.raw", .file)])])
        let blocker = try #require(blockers.first)
        #expect(blocker.kind == .app && blocker.appToQuit?.pid == 812 && blocker.name == "Darkroom")
    }

    @Test func aShellInATerminalIsNamedAfterTheTerminal() throws {
        let blockers = group([Sample.use(Sample.zsh, [(ssd + "/Projects", .folder)])])
        let shell = try #require(blockers.first)
        #expect(shell.kind == .shell(in: "Shellwise") && shell.name == "zsh")
        #expect(shell.appToQuit == nil)
        #expect(shell.app == Sample.shellwise) // for its icon
    }

    @Test func aCommandInATerminalIsNotAShell() throws {
        let blockers = group([
            Sample.use(Sample.rsync, [(ssd + "/Backup/notes.db", .file)]),
            // A shell with a file open, not just its folder, is a command too.
            Sample.use(Sample.zsh, [(ssd + "/Projects", .folder), (ssd + "/Projects/log.txt", .file)]),
        ])
        #expect(blockers.map(\.kind) == [.command(in: "Shellwise"), .command(in: "Shellwise")])
        #expect(blockers.map(\.name) == ["rsync", "zsh"])
        #expect(blockers.allSatisfy { $0.appToQuit == nil })
    }

    @Test func shellsInOneTerminalAreGroupedButDifferentTerminalsAreNot() {
        let otherTerminal = AppFacts(pid: 710, name: "Glasswing", bundleID: "com.example.glasswing", bundlePath: "/Applications/Glasswing.app")
        var apps = Sample.apps
        apps[710] = otherTerminal
        let second = Sample.process(903, "zsh", parent: 700, executable: "/bin/zsh")
        let third = Sample.process(904, "zsh", parent: 710, executable: "/bin/zsh")
        let blockers = group([
            Sample.use(Sample.zsh, [(ssd + "/A", .folder)]),
            Sample.use(second, [(ssd + "/B", .folder)]),
            Sample.use(third, [(ssd + "/C", .folder)]),
        ], apps: apps)
        #expect(blockers.count == 2)
        #expect(blockers.first { $0.kind == .shell(in: "Shellwise") }?.processes.count == 2)
        #expect(blockers.first { $0.kind == .shell(in: "Glasswing") }?.files.count == 1)
    }

    @Test func aToolInsideAnAppRunFromATerminalBelongsToTheTerminal() throws {
        // `swift build` in a terminal runs a compiler that lives inside a developer tool's app.
        // Quitting that app wouldn't stop the build, so it's the terminal's command.
        let studio = AppFacts(pid: 600, name: "Codeforge", bundleID: "com.example.codeforge", bundlePath: "/Applications/Codeforge.app")
        var apps = Sample.apps
        apps[600] = studio
        let compiler = Sample.process(905, "swift-frontend", parent: 901, executable: "/Applications/Codeforge.app/Contents/Developer/usr/bin/swift-frontend")
        let blocker = try #require(group([Sample.use(compiler, [(ssd + "/proj/main.swift", .file)])], apps: apps).first)
        #expect(blocker.kind == .command(in: "Shellwise") && blocker.appToQuit == nil)
        // The same program started by macOS, with no terminal behind it, is the app's.
        let helper = Sample.process(906, "swift-frontend", executable: compiler.executable)
        #expect(try #require(group([Sample.use(helper, [(ssd + "/a", .file)])], apps: apps).first).appToQuit == studio)
    }

    @Test func anAppWithoutAKnownLocationIsNeverQuit() throws {
        let loose = AppFacts(pid: 990, name: "Loose", bundleID: nil, bundlePath: nil)
        let blocker = try #require(group([Sample.use(Sample.process(990, "Loose", executable: "/usr/local/bin/loose"), [(ssd + "/a", .file)])], apps: [990: loose]).first)
        #expect(blocker.kind == .app && blocker.appToQuit == nil)
        #expect(Describe.advice(blocker, on: Sample.travelDrive) == "Quit Loose the way you usually would, or let it finish.")
    }

    @Test func partsOfMacOSAreExplainedNotQuit() throws {
        let photos = Sample.process(60, "photolibraryd", executable: "/System/Library/PrivateFrameworks/PhotoLibraryServices.framework/Versions/A/Support/photolibraryd")
        let thumbnails = Sample.process(61, "AudiovisualThumbnailExtension", executable: "/System/Library/ExtensionKit/Extensions/AudiovisualThumbnailExtension.appex/Contents/MacOS/AudiovisualThumbnailExtension")
        let images = Sample.process(62, "diskimages-helper", executable: "/System/Library/PrivateFrameworks/DiskImages.framework/Resources/diskimages-helper")
        let xprotect = Sample.process(63, "XProtect", executable: "/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/MacOS/XProtect")
        let blockers = group([
            Sample.use(Sample.mdworker, [(ssd + "/a", .file)]),
            Sample.use(photos, [(ssd + "/Photos Library.photoslibrary/database/Photos.sqlite", .file)]),
            Sample.use(thumbnails, [(ssd + "/clip.mov", .file)]),
            Sample.use(images, [(ssd + "/Installers/Tool.dmg", .file)]),
            Sample.use(xprotect, [(ssd + "/Tool.app/Contents/MacOS/Tool", .file)]),
        ])
        #expect(Set(blockers.map(\.kind)) == [.system(.spotlight), .system(.photos), .system(.quickLook), .system(.diskImage), .system(.securityCheck)])
        #expect(blockers.allSatisfy { $0.appToQuit == nil })
        #expect(blockers.first { $0.kind == .system(.spotlight) }?.name == "Spotlight")
    }

    @Test func aProgramThatOnlyCallsItselfMdsIsNotExcusedAsSpotlight() throws {
        let impostor = Sample.process(66, "mdworker_shared", executable: "/Users/someone/Downloads/mdworker_shared")
        let blocker = try #require(group([Sample.use(impostor, [(ssd + "/a", .file)])]).first)
        #expect(blocker.kind == .background(partOf: nil))
        #expect(SystemProcess.identify(Sample.process(1, "mds", executable: nil)) == nil)
        #expect(SystemProcess.identify(Sample.process(1, "Darkroom", executable: "/System/Applications/Darkroom")) == nil)
    }

    @Test func finderAndMacOSAppsAreNeverOfferedToQuit() {
        let blockers = group([
            Sample.use(Sample.process(401, "Finder", executable: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"), [(ssd + "/copying.zip", .file)]),
            Sample.use(Sample.process(402, "Dock", executable: "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"), [(ssd + "/x", .file)]),
        ])
        #expect(blockers.map(\.kind) == [.finder, .system(.macOS)])
        #expect(blockers.allSatisfy { $0.appToQuit == nil })
        #expect(blockers[1].name == "Dock")
    }

    @Test func anAppInSystemFoldersIsNeverQuitEvenIfMarkedAsAnApp() {
        let blocker = Blocker(id: "x", kind: .app, name: "Dock", app: Sample.dock, iconPath: nil, processes: [], files: [])
        #expect(blocker.appToQuit == nil)
    }

    @Test func anAppRunningFromTheDiskCanBeQuit() throws {
        let process = Sample.process(950, "Brushwork Installer", executable: "/Volumes/Brushwork/Brushwork Installer.app/Contents/MacOS/Brushwork Installer")
        let blocker = try #require(group([Sample.use(process, [(process.executable!, .program)])]).first)
        #expect(blocker.kind == .app && blocker.appToQuit == Sample.installerApp)
    }

    @Test func itselfIsNamedButNeverQuit() throws {
        let me = Sample.process(1234, "UnblockEject", executable: "/Volumes/Travel SSD/Unblock Eject.app/Contents/MacOS/UnblockEject")
        let blocker = try #require(group([Sample.use(me, [(me.executable!, .program)])]).first)
        #expect(blocker.kind == .itself && blocker.appToQuit == nil && blocker.name == "Unblock Eject")
    }

    @Test func backgroundProcessesSayWhichAppTheyBelongTo() {
        let agent = Sample.process(970, "SyncAgent", executable: "/Applications/CloudSync.app/Contents/Library/LoginItems/SyncAgent.app/Contents/MacOS/SyncAgent")
        let tool = Sample.process(971, "rsync", executable: "/usr/bin/rsync")
        let blockers = group([Sample.use(agent, [(ssd + "/sync", .folder)]), Sample.use(tool, [(ssd + "/b", .file)])])
        #expect(blockers.map(\.kind) == [.background(partOf: nil), .background(partOf: "CloudSync")])
        #expect(blockers[1].iconPath == "/Applications/CloudSync.app")
    }

    @Test func appsComeFirstThenTerminalsThenMacOS() {
        let blockers = group([
            Sample.use(Sample.mdworker, [(ssd + "/a", .file)]),
            Sample.use(Sample.zsh, [(ssd + "/b", .folder)]),
            Sample.use(Sample.darkroomProcess, [(ssd + "/c", .file)]),
            Sample.use(Sample.process(401, "Finder"), [(ssd + "/d", .file)]),
        ])
        #expect(blockers.map(\.name) == ["Darkroom", "zsh", "Finder", "Spotlight"])
    }

    @Test func parentLoopsAndDeadEndsDontHang() {
        let a = Sample.process(5000, "a", parent: 5001, executable: "/usr/local/bin/a")
        let b = Sample.process(5001, "b", parent: 5000, executable: "/usr/local/bin/b")
        let table = [a.pid: a, b.pid: b]
        #expect(Blockers.hostApp(of: a, apps: [:], parent: { table[$0] }) == nil)
        #expect(Blockers.hostApp(of: Sample.process(5002, "c", parent: 99999), apps: [:], parent: { _ in nil }) == nil)
        #expect(Blockers.hostApp(of: Sample.rsync, apps: Sample.apps, parent: { Sample.table[$0] }) == Sample.shellwise)
    }

    @Test(arguments: [
        ("/Applications/Big.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper", "/Applications/Big.app"),
        ("/Applications/Big.app", "/Applications/Big.app"),
        ("/Volumes/X/Setup.APP/Contents/MacOS/Setup", "/Volumes/X/Setup.APP"),
        ("/usr/bin/rsync", nil),
        ("/Users/me/apps.txt", nil),
    ] as [(String, String?)])
    func outermostApps(path: String, app: String?) {
        #expect(Blockers.outermostApp(path) == app)
    }

    @Test func theScannerOnlyListsWhatsOnThatDrive() {
        let processes = FakeProcesses(uses: [
            Sample.use(Sample.darkroomProcess, [(ssd + "/a.raw", .file), ("/Volumes/FIELD REC/b.wav", .file)]),
            Sample.use(Sample.zsh, [("/Volumes/FIELD REC", .folder)]),
        ], table: Sample.table)
        let scanner = DiskScanner(processes: processes, ownPID: nil)
        let report = scanner.report(Sample.travelDrive, apps: Sample.apps)
        #expect(report.blockers.map(\.name) == ["Darkroom"])
        #expect(report.blockers[0].files.map(\.path) == [ssd + "/a.raw"])
        #expect(!report.isFree)
        #expect(scanner.report(Sample.archiveDrive, apps: Sample.apps).isFree)
        #expect(report.id == "disk6")
    }

    @Test func openFilesSortByHowTheyreUsed() {
        let files = [
            OpenFile(path: "/v/z", use: .loaded), OpenFile(path: "/v/b", use: .file), OpenFile(path: "/v/a", use: .folder),
            OpenFile(path: "/v/a10", use: .file), OpenFile(path: "/v/a9", use: .file), OpenFile(path: "/v/app", use: .program),
        ]
        #expect(files.sorted().map(\.path) == ["/v/app", "/v/a9", "/v/a10", "/v/b", "/v/a", "/v/z"])
    }
}
