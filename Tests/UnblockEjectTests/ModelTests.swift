import Foundation
import Testing
@testable import EjectCore
@testable import UnblockEject

@MainActor
@Suite("Model")
struct ModelTests {
    @Test func listsEachDiskAndWhatsUsingIt() throws {
        let model = Gallery.model()
        #expect(model.reports.map(\.drive.name) == ["Travel SSD", "FIELD REC", "Brushwork 2.4"])
        let ssd = try #require(model.report("disk5"))
        #expect(ssd.blockers.map(Describe.title) == ["Darkroom", "zsh in Shellwise", "Spotlight"])
        #expect(model.report("disk7")?.isFree == true)
        #expect(model.report("disk8")?.blockers.first?.appToQuit == Gallery.brushwork)
        #expect(model.lastCheck == Gallery.now)
        // Volumes hidden from Finder aren't listed.
        #expect(model.report("disk10") == nil)
    }

    @Test func quitAsksTheAppOnce() throws {
        let control = RecordedQuits()
        let model = Gallery.model(control: control)
        let darkroom = try #require(model.report("disk5")?.blockers.first)
        model.quit(darkroom)
        model.quit(darkroom)
        #expect(control.quits == [812])
        #expect(model.isQuitting(Gallery.darkroom))
    }

    @Test func partsOfMacOSAndShellsAreNeverQuit() throws {
        let control = RecordedQuits()
        let model = Gallery.model(control: control)
        let blockers = try #require(model.report("disk5")?.blockers)
        for blocker in blockers.dropFirst() { model.quit(blocker) }
        #expect(control.quits.isEmpty)
    }

    @Test func anAppThatSaysNoIsntShownQuitting() throws {
        let control = RecordedQuits()
        control.answer = false
        let model = Gallery.model(control: control)
        model.quit(try #require(model.report("disk5")?.blockers.first))
        #expect(!model.isQuitting(Gallery.darkroom))
    }

    @Test func quittingEndsWhenTheAppQuitsOrAfterAWhile() throws {
        let processes = FakeProcesses(uses: Gallery.uses, table: Gallery.table)
        let model = Gallery.model(processes: processes)
        model.quit(try #require(model.report("disk5")?.blockers.first))
        model.quit(try #require(model.report("disk8")?.blockers.first))
        #expect(model.quitting.count == 2)

        // Brushwork's installer quits.
        model.runningApps = { Gallery.apps.filter { $0.key != 950 } }
        processes.uses.removeAll { $0.process.pid == 950 }
        model.refresh()
        #expect(model.quitting.keys.sorted() == [812])
        #expect(model.report("disk8")?.isFree == true)

        // Darkroom asked to save and you cancelled: after a while, Quit is offered again.
        model.now = { Gallery.now.addingTimeInterval(EjectModel.quitPatience + 1) }
        model.refresh()
        #expect(model.quitting.isEmpty)
    }

    @Test func ejectingAFreeDisk() async throws {
        let ejector = FakeEjector()
        let model = Gallery.model(ejector: ejector)
        let card = try #require(model.report("disk7")?.drive)
        #expect(await model.eject(card) == .ejected)
        #expect(ejector.ejected == ["disk7"])
        #expect(model.message?.text == "Ejected “FIELD REC”. It's safe to unplug.")
        #expect(model.message?.isProblem == false)
        #expect(!model.needsAttention)
        #expect(model.ejecting.isEmpty)
    }

    @Test func aBusyEjectSaysWhoAndAsksForAttention() async throws {
        let ejector = FakeEjector()
        ejector.result = .busy(message: nil)
        let model = Gallery.model(ejector: ejector)
        let ssd = try #require(model.report("disk5")?.drive)
        await model.eject(ssd)
        #expect(model.message?.text == "Couldn't eject “Travel SSD”: Darkroom, zsh in Shellwise and Spotlight still have files open on it.")
        #expect(model.message?.isProblem == true)
        #expect(model.needsAttention)
        model.dismissMessage()
        #expect(!model.needsAttention && model.message == nil)
    }

    @Test func attentionEndsWhenTheDiskIsGone() async throws {
        let ejector = FakeEjector()
        ejector.result = .notAllowed
        let model = Gallery.model(ejector: ejector)
        await model.eject(try #require(model.report("disk7")?.drive))
        #expect(model.needsAttention)
        let unplugged = Gallery.model(volumes: [Gallery.ssd], ejector: ejector)
        await unplugged.eject(Drive(wholeDisk: "disk7", volumes: [Gallery.card]))
        #expect(!unplugged.needsAttention)
    }

    @Test func messagesFadeAfterAWhile() async throws {
        let model = Gallery.model()
        await model.eject(try #require(model.report("disk7")?.drive))
        model.refresh()
        #expect(model.message != nil)
        model.now = { Gallery.now.addingTimeInterval(EjectModel.messageLifetime + 1) }
        model.refresh()
        #expect(model.message == nil)
    }

    @Test func hiddenVolumesOnAListedDiskAreChecked() throws {
        let hidden = Volume(path: "/Volumes/.snap", name: "Snap", device: "disk6s9", wholeDisk: "disk5", kind: .externalDrive, isHidden: true)
        let processes = FakeProcesses(uses: [Gallery.use(Gallery.darkroomProcess, [("/Volumes/.snap/x", .file)])], table: Gallery.table)
        let model = Gallery.model(volumes: [Gallery.ssd, hidden], processes: processes)
        let report = try #require(model.report("disk5"))
        #expect(report.drive.name == "Travel SSD")
        #expect(report.blockers.map(\.name) == ["Darkroom"])
    }

    @Test func aNewDiskWithTheSameNameDoesntInheritAnAlert() async throws {
        let ejector = FakeEjector()
        ejector.result = .busy(message: nil)
        let model = Gallery.model(volumes: [Gallery.card], ejector: ejector)
        await model.eject(try #require(model.report("disk7")?.drive))
        #expect(model.needsAttention)
        let other = Volume(path: "/Volumes/OTHER CARD", name: "OTHER CARD", device: "disk7s1", wholeDisk: "disk7", kind: .memoryCard)
        let later = EjectModel(volumes: FakeVolumes(all: [other]), scanner: model.scanner, ejector: ejector, control: RecordedQuits(), runningApps: { [:] })
        later.refresh()
        await later.eject(Drive(wholeDisk: "disk7", volumes: [Gallery.card]))
        #expect(!later.needsAttention)
    }

    @Test func noDisks() {
        let model = Gallery.model(volumes: [])
        #expect(model.reports.isEmpty)
    }
}
