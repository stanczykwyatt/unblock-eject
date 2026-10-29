/// Parts of macOS that hold disks open for a while, named in words people recognize.
public enum SystemProcess: String, Hashable, Sendable, Codable, CaseIterable {
    case spotlight
    case timeMachine
    case quickLook
    case photos
    case mediaLibrary
    case diskImage
    case securityCheck
    case macOS

    /// Process names checked against macOS 15. Most of these run in the background with names like
    /// "mdworker_shared" that never appear anywhere else.
    static let byName: [String: SystemProcess] = [
        "mds": .spotlight,
        "mds_stores": .spotlight,
        "mdworker": .spotlight,
        "mdworker_shared": .spotlight,
        "mdsync": .spotlight,
        "mdbulkimport": .spotlight,
        "corespotlightd": .spotlight,
        "Spotlight": .spotlight,
        "backupd": .timeMachine,
        "backupd-helper": .timeMachine,
        "TMHelperAgent": .timeMachine,
        "QuickLookUIService": .quickLook,
        "quicklookd": .quickLook,
        "QuickLookSatellite": .quickLook,
        "ExternalQuickLookSatellite": .quickLook,
        "com.apple.quicklook.ThumbnailsAgent": .quickLook,
        "photolibraryd": .photos,
        "photoanalysisd": .photos,
        "mediaanalysisd": .photos,
        "cloudphotod": .photos,
        "AMPLibraryAgent": .mediaLibrary,
        "diskimages-helper": .diskImage,
        "diskimagesiod": .diskImage,
        "XProtect": .securityCheck,
        "XprotectService": .securityCheck,
        "XProtectPluginService": .securityCheck,
        "syspolicyd": .securityCheck,
    ]

    /// Which part of macOS a process is, if it's one. Only programs inside macOS's own protected
    /// folders count, so a program that merely calls itself "mds" isn't excused as Spotlight.
    public static func identify(_ process: ProcessFacts) -> SystemProcess? {
        guard let executable = process.executable, isProtected(executable) else { return nil }
        if let known = byName[process.name] { return known }
        if process.name.hasSuffix("ThumbnailExtension") { return .quickLook }
        return nil
    }

    /// Folders only macOS can change, guarded by System Integrity Protection.
    static func isProtected(_ path: String) -> Bool {
        ["/System", "/usr/libexec", "/usr/sbin", "/usr/bin", "/Library/Apple/System"].contains { Paths.isInside(path, $0) }
    }

    /// What people call it.
    public var name: String {
        switch self {
        case .spotlight: "Spotlight"
        case .timeMachine: "Time Machine"
        case .quickLook: "Quick Look"
        case .photos: "Photos library"
        case .mediaLibrary: "Music and TV library"
        case .diskImage: "Disk image"
        case .securityCheck: "Malware check"
        case .macOS: "macOS"
        }
    }
}
