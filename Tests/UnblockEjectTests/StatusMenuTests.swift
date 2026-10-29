import AppKit
import Testing
@testable import EjectCore
@testable import UnblockEject

@MainActor
final class RecordedActions: StatusMenuActions {
    var calls: [String] = []
    func eject(_ drive: Drive) { calls.append("eject \(drive.id)") }
    func quit(_ blocker: Blocker) { calls.append("quit \(blocker.name)") }
    func openWindow() { calls.append("window") }
    func toggleOpenAtLogin() { calls.append("login") }
    func showAbout() { calls.append("about") }
}

/// The menu, built into an NSMenu that's never shown.
@MainActor
@Suite("Menu")
struct StatusMenuTests {
    let actions = RecordedActions()

    private func build(_ model: EjectModel) -> NSMenu {
        let statusMenu = StatusMenu(model: model, icons: Gallery.icons(), actions: actions)
        statusMenu.opensAtLogin = { true }
        let menu = NSMenu()
        statusMenu.build(into: menu)
        // Keeps the builder alive for the menu's targets, as the app delegate does.
        objc_setAssociatedObject(menu, "builder", statusMenu, .OBJC_ASSOCIATION_RETAIN)
        return menu
    }

    /// Matches the first line, since two-line items carry both lines in their title.
    private func item(_ menu: NSMenu, _ title: String) throws -> NSMenuItem {
        try #require(menu.items.first { firstLine($0) == title }, "No item titled \(title)")
    }

    private func firstLine(_ item: NSMenuItem) -> String {
        item.title.components(separatedBy: "\n")[0]
    }

    private func click(_ item: NSMenuItem) {
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
    }

    @Test func noDisks() throws {
        let menu = build(Gallery.model(volumes: []))
        #expect(menu.items.first?.title == "No disks to eject")
        #expect(try item(menu, "Open Unblock Eject…").isEnabled)
        #expect(try item(menu, "Open at Login").state == .on)
    }

    @Test func eachDiskWithItsBlockersAndEject() throws {
        let menu = build(Gallery.model())
        let headers = menu.items.filter(\.isSectionHeader).map(\.title)
        #expect(headers == ["Travel SSD", "FIELD REC", "Brushwork 2.4"])
        #expect(menu.items.contains { $0.title.replacingOccurrences(of: "\n", with: " ") == "External drive · 1 TB · In use by Darkroom, zsh in Shellwise and Spotlight" && !$0.isEnabled })
        #expect(menu.items.contains { $0.title.hasPrefix("Memory card · 63.85 GB · Nothing is using it") })

        let darkroom = try item(menu, "Darkroom")
        #expect(darkroom.attributedTitle?.string == "Darkroom\n4 files open · through Darkroom Renderer")
        #expect(darkroom.image?.size == NSSize(width: 20, height: 20))
        let shell = try item(menu, "zsh in Shellwise")
        #expect(shell.attributedTitle?.string.hasSuffix("Working in Projects/tidepool-site") == true)

        click(try item(menu, "Eject “FIELD REC”"))
        #expect(actions.calls == ["eject disk7"])
    }

    @Test func aBlockersFilesAdviceAndQuit() throws {
        let menu = build(Gallery.model())
        let details = try #require(try item(menu, "Darkroom").submenu)
        let titles = details.items.map(\.title)
        #expect(Array(titles.prefix(3)) == ["Catalogs/Coast.dkcat", "Shoots/2026-04 Coast/IMG_0412.raw", "Shoots/2026-04 Coast/IMG_0418.raw"])
        #expect(titles.contains { $0.hasPrefix("Quit Darkroom to free the disk.") })
        let quit = try item(details, "Quit Darkroom")
        click(quit)
        #expect(actions.calls == ["quit Darkroom"])
    }

    @Test func noQuitForShellsOrMacOS() throws {
        let menu = build(Gallery.model())
        for title in ["zsh in Shellwise", "Spotlight"] {
            let details = try #require(try item(menu, title).submenu)
            #expect(!details.items.contains { $0.title.hasPrefix("Quit ") && $0.isEnabled })
        }
        let spotlight = try #require(try item(menu, "Spotlight").submenu)
        #expect(spotlight.items.contains { $0.title.contains("Spotlight is indexing it") })
    }

    @Test func quittingAndEjectingShowTheyreUnderway() throws {
        let model = Gallery.model()
        model.quit(try #require(model.report("disk5")?.blockers.first))
        let menu = build(model)
        let details = try #require(try item(menu, "Darkroom").submenu)
        let quitting = try item(details, "Quitting Darkroom…")
        #expect(!quitting.isEnabled)
    }

    @Test func theLastEjectIsAtTheTop() async throws {
        let ejector = FakeEjector()
        ejector.result = .busy(message: nil)
        let model = Gallery.model(ejector: ejector)
        await model.eject(try #require(model.report("disk5")?.drive))
        let menu = build(model)
        #expect(menu.items.first?.title.hasPrefix("Couldn't eject “Travel SSD”:") == true)
        #expect(menu.items.first?.isEnabled == false)
        // Wrapped, since menus don't wrap long lines themselves.
        #expect(menu.items.first?.title.components(separatedBy: "\n").allSatisfy { $0.count <= StatusMenu.lineLength + 20 } == true)
    }

    @Test func longFileListsAreCut() throws {
        let many = (1...20).map { ("/Volumes/FIELD REC/take\($0).wav", OpenFile.Use.file) }
        let processes = FakeProcesses(uses: [Gallery.use(Gallery.darkroomProcess, many)], table: Gallery.table)
        let menu = build(Gallery.model(processes: processes))
        let details = try #require(try item(menu, "Darkroom").submenu)
        #expect(details.items.contains { $0.title == "and 8 more" })
        #expect(details.items.filter { $0.title.hasPrefix("take") }.count == StatusMenu.fileLimit)
    }

    @Test func actionsReachTheDelegate() throws {
        let menu = build(Gallery.model())
        for title in ["Open Unblock Eject…", "Open at Login", "About Unblock Eject"] {
            click(try item(menu, title))
        }
        #expect(actions.calls == ["window", "login", "about"])
    }

    @Test func wrapping() {
        #expect(StatusMenu.wrap("one two three", width: 7) == "one two\nthree")
        #expect(StatusMenu.wrap("short") == "short")
        #expect(StatusMenu.wrap("averyveryverylongword x", width: 5) == "averyveryverylongword\nx")
        #expect(StatusMenu.wrap("") == "")
    }
}
