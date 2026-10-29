import AppKit

/// A running app, as macOS's list of apps describes it.
public struct AppFacts: Hashable, Sendable, Codable {
    public enum Presence: String, Hashable, Sendable, Codable {
        /// In the Dock.
        case regular
        /// A menu bar app or other app without a Dock icon.
        case accessory
        /// Runs in the background with no interface.
        case background
    }

    public let pid: Int32
    public let name: String
    public let bundleID: String?
    /// Where the app is, like `/Applications/Preview.app`.
    public let bundlePath: String?
    public let presence: Presence
    /// When it started, to tell it apart from a later app that gets the same process ID.
    public let launchDate: Date?

    public init(
        pid: Int32, name: String, bundleID: String? = nil, bundlePath: String? = nil, presence: Presence = .regular, launchDate: Date? = nil
    ) {
        self.pid = pid
        self.name = name
        self.bundleID = bundleID
        self.bundlePath = bundlePath
        self.presence = presence
        self.launchDate = launchDate
    }

    /// Part of macOS, which is never offered to quit.
    public var isSystem: Bool {
        guard let bundlePath else { return false }
        return Paths.isInside(bundlePath, "/System/Library") || Paths.isInside(bundlePath, "/Library/Apple")
    }
}

public enum RunningApps {
    /// Every running app by process ID, read from macOS's list of apps. Nothing is asked of the
    /// apps themselves.
    @MainActor
    public static func snapshot() -> [Int32: AppFacts] {
        var apps: [Int32: AppFacts] = [:]
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier > 0 {
            let presence: AppFacts.Presence = switch app.activationPolicy {
            case .regular: .regular
            case .accessory: .accessory
            default: .background
            }
            let path = app.bundleURL?.path
            let name = app.localizedName ?? path.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? "App \(app.processIdentifier)"
            apps[app.processIdentifier] = AppFacts(
                pid: app.processIdentifier, name: name, bundleID: app.bundleIdentifier, bundlePath: path, presence: presence,
                launchDate: app.launchDate
            )
        }
        return apps
    }
}
