import AppKit
import EjectCore
import ServiceManagement

/// What the menu's items do. The app delegate does them; tests record them.
@MainActor
protocol StatusMenuActions: AnyObject {
    func eject(_ drive: Drive)
    func quit(_ blocker: Blocker)
    func openWindow()
    func toggleOpenAtLogin()
    func showAbout()
}

/// Builds the menu bar menu fresh each time it opens, right after looking again, so it's never stale.
@MainActor
final class StatusMenu: NSObject {
    private let model: EjectModel
    private let icons: AppIcons
    private weak var actions: StatusMenuActions?
    var opensAtLogin: () -> Bool = { SMAppService.mainApp.status == .enabled }

    static let fileLimit = 12
    /// Menus don't wrap, so long lines are broken by hand at about this many characters.
    static let lineLength = 58

    init(model: EjectModel, icons: AppIcons, actions: StatusMenuActions) {
        self.model = model
        self.icons = icons
        self.actions = actions
    }

    func build(into menu: NSMenu) {
        menu.removeAllItems()
        if let message = model.message {
            menu.addItem(disabled(message.text, wrapped: true))
            menu.addItem(.separator())
        }

        if model.reports.isEmpty {
            menu.addItem(disabled("No disks to eject"))
            menu.addItem(disabled("External drives, memory cards and disk images show up here.", wrapped: true))
        }
        for (index, report) in model.reports.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            addDrive(report, to: menu)
        }

        menu.addItem(.separator())
        menu.addItem(item("Open Unblock Eject…", #selector(openWindow), key: "o"))
        let login = item("Open at Login", #selector(toggleOpenAtLogin))
        login.state = opensAtLogin() ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("About Unblock Eject", #selector(showAbout)))
        menu.addItem(NSMenuItem(title: "Quit Unblock Eject", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    // MARK: Items

    private func addDrive(_ report: DriveReport, to menu: NSMenu) {
        let drive = report.drive
        let header = NSMenuItem.sectionHeader(title: Describe.safe(drive.name, limit: 60))
        menu.addItem(header)
        menu.addItem(disabled("\(Describe.details(drive)) · \(Describe.status(report))", wrapped: true))
        for blocker in report.blockers {
            menu.addItem(blockerItem(blocker, on: drive))
        }
        let ejecting = model.ejecting.contains(drive.id)
        let eject = item(ejecting ? "Ejecting…" : "Eject “\(Describe.safe(drive.name, limit: 40))”", #selector(eject(_:)))
        eject.representedObject = drive
        eject.isEnabled = !ejecting
        eject.image = NSImage(systemSymbolName: "eject", accessibilityDescription: nil)
        menu.addItem(eject)
    }

    private func blockerItem(_ blocker: Blocker, on drive: Drive) -> NSMenuItem {
        let title = Describe.title(blocker)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = twoLines(title, Describe.summary(blocker, on: drive))
        item.image = icons.icon(for: blocker, size: 20)
        let details = NSMenu()
        for file in blocker.files.prefix(Self.fileLimit) {
            details.addItem(disabled(Describe.file(file, on: drive)))
        }
        if blocker.files.count > Self.fileLimit {
            details.addItem(disabled("and \(Describe.count(blocker.files.count - Self.fileLimit, "more", plural: "more"))"))
        }
        details.addItem(.separator())
        details.addItem(disabled(Describe.advice(blocker, on: drive), wrapped: true))
        if let app = blocker.appToQuit {
            details.addItem(.separator())
            let quitting = model.isQuitting(app)
            let quit = self.item(quitting ? "Quitting \(Describe.safe(app.name, limit: 60))…" : "Quit \(Describe.safe(app.name, limit: 60))", #selector(quit(_:)))
            quit.representedObject = blocker
            quit.isEnabled = !quitting
            details.addItem(quit)
        }
        item.submenu = details
        return item
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabled(_ title: String, wrapped: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: wrapped ? Self.wrap(title) : title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func twoLines(_ first: String, _ second: String) -> NSAttributedString {
        let text = NSMutableAttributedString(string: first, attributes: [.font: NSFont.menuFont(ofSize: 0)])
        guard !second.isEmpty else { return text }
        text.append(NSAttributedString(string: "\n" + second, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return text
    }

    /// Breaks text into lines of about `width` characters, between words.
    static func wrap(_ text: String, width: Int = lineLength) -> String {
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: true) {
            if !line.isEmpty && line.count + 1 + word.count > width {
                lines.append(line)
                line = ""
            }
            line += line.isEmpty ? String(word) : " " + word
        }
        if !line.isEmpty { lines.append(line) }
        return lines.joined(separator: "\n")
    }

    // MARK: Actions

    @objc private func openWindow() { actions?.openWindow() }
    @objc private func toggleOpenAtLogin() { actions?.toggleOpenAtLogin() }
    @objc private func showAbout() { actions?.showAbout() }

    @objc private func eject(_ sender: NSMenuItem) {
        guard let drive = sender.representedObject as? Drive else { return }
        actions?.eject(drive)
    }

    @objc private func quit(_ sender: NSMenuItem) {
        guard let blocker = sender.representedObject as? Blocker else { return }
        actions?.quit(blocker)
    }
}
