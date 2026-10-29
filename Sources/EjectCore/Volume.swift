import Foundation

/// A mounted volume you can eject: on an external drive, a memory card, or a disk image.
public struct Volume: Hashable, Sendable, Identifiable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        case externalDrive
        case memoryCard
        case diskImage
    }

    /// Where it's mounted, like `/Volumes/Travel SSD`.
    public let path: String
    public let name: String
    /// Its BSD name, like `disk5s1`.
    public let device: String
    /// The physical disk it's on, like `disk4`. Ejecting takes every volume on that disk with it.
    public let wholeDisk: String
    /// The disk macOS presents it on, like `disk5`. For APFS that's a container on top of the
    /// physical disk; for other formats it's the physical disk itself.
    public let container: String
    public let kind: Kind
    /// Total size in bytes, if macOS said.
    public let size: Int64?
    /// Mounted so Finder doesn't show it. Left out unless asked for.
    public let isHidden: Bool
    /// The volume's own ID, so a different disk that gets the same BSD name is never ejected
    /// in its place.
    public let uuid: String?

    public var id: String { path }

    public init(
        path: String, name: String, device: String, wholeDisk: String, container: String? = nil, kind: Kind, size: Int64? = nil,
        isHidden: Bool = false, uuid: String? = nil
    ) {
        self.path = path
        self.name = name
        self.device = device
        self.wholeDisk = wholeDisk
        self.container = container ?? wholeDisk
        self.kind = kind
        self.size = size
        self.isHidden = isHidden
        self.uuid = uuid
    }

    /// Whether `path` is this volume's mount point or anything inside it.
    public func contains(_ path: String) -> Bool {
        Paths.isInside(path, self.path)
    }
}

/// One line of the mount table, as `getmntinfo` reports it.
public struct MountEntry: Hashable, Sendable {
    public let path: String
    /// Where it's mounted from, like `/dev/disk5s1`, or `map auto_home` for things that aren't disks.
    public let source: String
    public let fileSystem: String
    public let isHidden: Bool
    public let size: Int64?

    public init(path: String, source: String, fileSystem: String, isHidden: Bool = false, size: Int64? = nil) {
        self.path = path
        self.source = source
        self.fileSystem = fileSystem
        self.isHidden = isHidden
        self.size = size
    }

    /// The BSD name for a disk, or nil for something that isn't one.
    public var device: String? {
        guard source.hasPrefix("/dev/disk") else { return nil }
        return String(source.dropFirst("/dev/".count))
    }
}

/// What Disk Arbitration says about the disk a volume is on.
public struct DiskFacts: Hashable, Sendable {
    public var volumeName: String?
    public var volumeUUID: String?
    public var ejectable: Bool
    public var removable: Bool
    /// Nil when macOS doesn't say, as for disk images.
    public var isInternal: Bool?
    public var model: String?
    public var connection: String?
    /// The disk Disk Arbitration says it's on, which for APFS is the container.
    public var wholeDisk: String?
    /// The physical disk under that, from the I/O Registry.
    public var physicalDisk: String?

    public init(
        volumeName: String? = nil, volumeUUID: String? = nil, ejectable: Bool = false, removable: Bool = false, isInternal: Bool? = nil,
        model: String? = nil, connection: String? = nil, wholeDisk: String? = nil, physicalDisk: String? = nil
    ) {
        self.volumeName = volumeName
        self.volumeUUID = volumeUUID
        self.ejectable = ejectable
        self.removable = removable
        self.isInternal = isInternal
        self.model = model
        self.connection = connection
        self.wholeDisk = wholeDisk
        self.physicalDisk = physicalDisk
    }

    var isDiskImage: Bool {
        model == "Disk Image" || connection == "Virtual Interface"
    }

    var isMemoryCard: Bool {
        guard let connection else { return false }
        return connection == "Secure Digital" || connection.hasPrefix("SD")
    }
}

/// Decides which mounted volumes are ones you'd eject, the same ones Finder shows an eject button for.
public enum VolumeFilter {
    public static func volume(for mount: MountEntry, facts: DiskFacts?, includeHidden: Bool = false) -> Volume? {
        guard let device = mount.device, let facts else { return nil }
        // The startup disk and macOS's own volumes are never ejected.
        if mount.path == "/" || Paths.isInside(mount.path, "/System/Volumes") { return nil }
        if mount.isHidden && !includeHidden { return nil }
        let kind: Volume.Kind
        if facts.isDiskImage {
            kind = .diskImage
        } else if facts.isMemoryCard {
            kind = .memoryCard
        } else if facts.ejectable || facts.removable || facts.isInternal == false {
            kind = .externalDrive
        } else {
            return nil
        }
        let fallback = (mount.path as NSString).lastPathComponent
        let name = facts.volumeName.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        let container = facts.wholeDisk ?? Self.wholeDisk(of: device)
        return Volume(
            path: mount.path, name: name, device: device, wholeDisk: facts.physicalDisk ?? container, container: container,
            kind: kind, size: mount.size, isHidden: mount.isHidden, uuid: facts.volumeUUID
        )
    }

    /// `disk5s1` is on `disk5`.
    public static func wholeDisk(of device: String) -> String {
        guard device.hasPrefix("disk") else { return device }
        let rest = device.dropFirst(4)
        let number = rest.prefix { $0.isNumber }
        return number.isEmpty ? device : "disk" + number
    }
}

/// A disk you eject as one: every volume on it goes together.
public struct Drive: Hashable, Sendable, Identifiable {
    public let wholeDisk: String
    public let volumes: [Volume]

    public var id: String { wholeDisk }

    public init(wholeDisk: String, volumes: [Volume]) {
        self.wholeDisk = wholeDisk
        self.volumes = volumes
    }

    /// The volumes Finder shows. Hidden ones on the same disk are still checked, since ejecting
    /// takes them too, but aren't named.
    public var shownVolumes: [Volume] {
        let shown = volumes.filter { !$0.isHidden }
        return shown.isEmpty ? volumes : shown
    }

    /// Whether Finder shows any of its volumes.
    public var isShown: Bool { volumes.contains { !$0.isHidden } }

    public var name: String {
        let names = shownVolumes.map(\.name)
        switch names.count {
        case 0: return wholeDisk
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }

    public var kind: Volume.Kind { shownVolumes.first?.kind ?? .externalDrive }
    public var mountPoints: [String] { volumes.map(\.path) }

    public func contains(_ path: String) -> Bool {
        volumes.contains { $0.contains(path) }
    }

    /// The volume a path is on, for showing the path from the top of that volume.
    public func volume(containing path: String) -> Volume? {
        // The longest mount point wins, in case one volume is mounted inside another.
        volumes.filter { $0.contains(path) }.max { $0.path.count < $1.path.count }
    }

    /// Volumes grouped by the disk they're on, in the order they were mounted.
    public static func group(_ volumes: [Volume]) -> [Drive] {
        var order: [String] = []
        var byDisk: [String: [Volume]] = [:]
        for volume in volumes {
            if byDisk[volume.wholeDisk] == nil { order.append(volume.wholeDisk) }
            byDisk[volume.wholeDisk, default: []].append(volume)
        }
        return order.map { Drive(wholeDisk: $0, volumes: byDisk[$0]!) }
    }
}

enum Paths {
    /// Whether `path` is `folder` or inside it, comparing whole path components.
    static func isInside(_ path: String, _ folder: String) -> Bool {
        if folder == "/" { return path.hasPrefix("/") }
        let folder = folder.hasSuffix("/") ? String(folder.dropLast()) : folder
        return path == folder || path.hasPrefix(folder + "/")
    }
}
