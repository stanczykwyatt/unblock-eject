import AppKit
import EjectCore
import SwiftUI

/// The main window: every disk you can eject, what's using each, a Quit button for each app
/// that is, and an Eject button for each disk.
struct EjectView: View {
    @Bindable var model: EjectModel
    let icons: AppIcons
    var now: () -> Date = Date.init
    var eject: (Drive) -> Void = { _ in }
    var quit: (Blocker) -> Void = { _ in }
    var refresh: () -> Void = {}
    /// The Eject button's tint when a disk is free. Your accent color in the app; a fixed blue in the screenshots.
    var tint = Color.accentColor

    static let fileLimit = 4

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let message = model.message {
                banner(message)
                Divider()
            }
            if model.reports.isEmpty {
                ContentUnavailableView {
                    Label("No disks to eject", systemImage: "eject")
                } description: {
                    Text("External drives, memory cards and disk images show up here once they're mounted.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(model.reports) { report in
                            card(report)
                        }
                    }
                    .padding(16)
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 360)
        // The window draws this anyway; drawing it here too keeps off-screen renders right in dark mode.
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.reports.isEmpty ? "Unblock Eject" : Describe.count(model.reports.count, "disk") + " to eject")
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(action: refresh) {
                Label("Check Again", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var subtitle: String {
        let busy = model.reports.filter { !$0.isFree }.count
        var parts: [String] = []
        if !model.reports.isEmpty {
            parts.append(busy == 0 ? "All free to eject" : "\(busy) in use")
        }
        if let checked = model.lastCheck {
            parts.append("checked \(Describe.relative(checked, now: now()))")
        }
        return parts.isEmpty ? "Looking…" : parts.joined(separator: " · ")
    }

    private func banner(_ message: EjectModel.Message) -> some View {
        HStack(spacing: 8) {
            Image(systemName: message.isProblem ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(message.isProblem ? Color.orange : Color.green)
            Text(message.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { model.dismissMessage() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss")
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(message.isProblem ? Color.orange.opacity(0.1) : Color.green.opacity(0.08))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Label("Quit asks each app the normal way. Nothing is ever force-quit or force-ejected.", systemImage: "hand.raised")
            Spacer()
            Text("No internet access")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Disks

    private func card(_ report: DriveReport) -> some View {
        let drive = report.drive
        let ejecting = model.ejecting.contains(drive.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: AppIcons.symbolName(drive.kind))
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Describe.safe(drive.name, limit: 80))
                        .font(.headline)
                    Text(Describe.details(drive) + " · " + Describe.status(report))
                        .font(.callout)
                        .foregroundStyle(report.isFree ? Color.secondary : Color.orange)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                if report.isFree {
                    Button { eject(drive) } label: {
                        Label(ejecting ? "Ejecting…" : "Eject", systemImage: "eject.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .disabled(ejecting)
                } else {
                    Button { eject(drive) } label: {
                        Label(ejecting ? "Ejecting…" : "Try to Eject", systemImage: "eject")
                    }
                    .disabled(ejecting)
                    .help("macOS refuses while anything has a file open on it.")
                }
            }
            .padding(14)
            if !report.isFree {
                Divider().padding(.leading, 60)
                ForEach(report.blockers) { blocker in
                    row(blocker, on: drive)
                    if blocker.id != report.blockers.last?.id {
                        Divider().padding(.leading, 60)
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
    }

    private func row(_ blocker: Blocker, on drive: Drive) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: icons.icon(for: blocker, size: 32))
                .resizable()
                .frame(width: 32, height: 32)
                .foregroundStyle(.secondary)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Describe.title(blocker)).font(.body.weight(.semibold))
                    Text(Describe.summary(blocker, on: drive)).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Text(Describe.advice(blocker, on: drive))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(blocker.files.prefix(Self.fileLimit), id: \.self) { file in
                        Text(Describe.file(file, on: drive))
                    }
                    if blocker.files.count > Self.fileLimit {
                        Text("and \(Describe.count(blocker.files.count - Self.fileLimit, "more", plural: "more"))")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 2)
                .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            if let app = blocker.appToQuit {
                let quitting = model.isQuitting(app)
                Button(quitting ? "Quitting…" : "Quit") { quit(blocker) }
                    .disabled(quitting)
                    .help("Asks \(Describe.safe(app.name, limit: 60)) to quit, the same as its own Quit command.")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// The window, made the first time it's opened and kept for next time.
@MainActor
final class EjectWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let makeView: () -> EjectView
    /// Called when you close the window.
    var onClose: (() -> Void)?
    /// Called when the window comes to the front.
    var onActivate: (() -> Void)?

    init(makeView: @escaping () -> EjectView) {
        self.makeView = makeView
    }

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onActivate?()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: makeView()))
        window.title = "Unblock Eject"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 760, height: 560))
        if !window.setFrameUsingName("EjectWindow") {
            window.center()
        }
        window.setFrameAutosaveName("EjectWindow")
        return window
    }
}
