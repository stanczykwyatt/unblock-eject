import AppKit
import EjectCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, StatusMenuActions {
    private let preferences = Preferences()
    private let menu = NSMenu()
    private let icons = AppIcons()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private lazy var model = EjectModel(control: WorkspaceApps(), runningApps: { RunningApps.snapshot() })
    private lazy var statusMenu = StatusMenu(model: model, icons: icons, actions: self)
    private lazy var window = EjectWindowController { [unowned self] in
        EjectView(
            model: model, icons: icons,
            eject: { [unowned self] in eject($0) },
            quit: { [unowned self] in quit($0) },
            refresh: { [unowned self] in refresh() }
        )
    }

    /// How often to look again while the window is open, so a disk shows as free soon after the
    /// app using it quits. Nothing runs while the window is closed.
    static let windowRefresh: TimeInterval = 2

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        statusItem.menu = menu
        refresh()

        // Gives the keyboard back to the app you were using.
        window.onClose = { [weak self] in
            self?.stopWatching()
            NSApp.hide(nil)
        }
        window.onActivate = { [weak self] in self?.refresh() }

        // Disks coming and going, and apps quitting, change what's listed.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }

        // The first time, open at login like most menu bar utilities, and show the window so it's
        // clear what the app does. Turn off login in the menu.
        if !preferences.launchedBefore {
            preferences.launchedBefore = true
            try? SMAppService.mainApp.register()
            openWindow()
        }
    }

    private func refresh() {
        model.refresh()
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        button.image = StatusIcon.image(alert: model.needsAttention)
        var tip = "Unblock Eject"
        let busy = model.reports.filter { !$0.isFree }
        if model.reports.isEmpty {
            tip += "\nNo disks to eject."
        } else if busy.isEmpty {
            tip += "\n" + (model.reports.count == 1 ? "Free to eject." : "All \(model.reports.count) disks are free to eject.")
        } else {
            tip += "\n" + busy.map { "\(Describe.safe($0.drive.name, limit: 40)): \(Describe.status($0))" }.joined(separator: "\n")
        }
        button.toolTip = tip
    }

    private func startWatching() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.windowRefresh, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.window.isVisible else { return }
                self.refresh()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
        statusMenu.build(into: menu)
    }

    // MARK: StatusMenuActions

    func eject(_ drive: Drive) {
        Task {
            let result = await model.eject(drive)
            updateStatusItem()
            // When it couldn't, show what's in the way. A menu would already be closed.
            if result != .ejected && result != .gone {
                openWindow()
            }
        }
    }

    func quit(_ blocker: Blocker) {
        model.quit(blocker)
        updateStatusItem()
    }

    func openWindow() {
        refresh()
        window.show()
        startWatching()
    }

    func toggleOpenAtLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }

    func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "Free and open source. No internet access.\ngithub.com/stanczykwyatt/unblock-eject",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }
}
