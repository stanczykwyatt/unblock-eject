import DiskArbitration
import Foundation
import IOKit

/// The volumes mounted right now, read from the kernel's mount table and described by Disk
/// Arbitration. Neither opens anything on the disks, so a slow or sleeping drive isn't woken.
public protocol VolumeSource: Sendable {
    func volumes(includeHidden: Bool) -> [Volume]
}

public struct MountTable: VolumeSource {
    public init() {}

    public func volumes(includeHidden: Bool = false) -> [Volume] {
        let session = DASessionCreate(kCFAllocatorDefault)
        return Self.mounts().compactMap { mount in
            guard let device = mount.device else { return nil }
            let facts = session.flatMap { Self.facts(device: device, session: $0) }
            return VolumeFilter.volume(for: mount, facts: facts, includeHidden: includeHidden)
        }
    }

    /// Every mount, without waiting on any file system to answer.
    public static func mounts() -> [MountEntry] {
        var buffer: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&buffer, MNT_NOWAIT)
        guard count > 0, let buffer else { return [] }
        return UnsafeBufferPointer(start: buffer, count: Int(count)).map { entry in
            let blocks = Int64(entry.f_blocks), blockSize = Int64(entry.f_bsize)
            return MountEntry(
                path: string(entry.f_mntonname),
                source: string(entry.f_mntfromname),
                fileSystem: string(entry.f_fstypename),
                isHidden: entry.f_flags & UInt32(MNT_DONTBROWSE) != 0,
                size: blocks > 0 && blockSize > 0 ? blocks.multipliedReportingOverflow(by: blockSize).partialValue : nil
            )
        }
    }

    /// Copies macOS mounts of apps from a volume. An app opened from a downloaded disk image runs
    /// from a read-only copy at a random path (App Translocation), mounted from the app on the
    /// volume, so what it has open is under that copy instead.
    public static func translocations(inside mountPoints: [String], mounts: [MountEntry]) -> [(path: String, source: String)] {
        mounts.compactMap { mount in
            guard mount.fileSystem == "nullfs", mount.source.hasPrefix("/"),
                  mountPoints.contains(where: { Paths.isInside(mount.source, $0) }) else { return nil }
            return (mount.path, mount.source)
        }
    }

    static func facts(device: String, session: DASession) -> DiskFacts? {
        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, device),
              let description = DADiskCopyDescription(disk) as? [String: Any] else { return nil }
        func value<T>(_ key: CFString) -> T? { description[key as String] as? T }
        var whole: String?
        if let wholeDisk = DADiskCopyWholeDisk(disk), let name = DADiskGetBSDName(wholeDisk) {
            whole = String(cString: name)
        }
        let uuid = (description[kDADiskDescriptionVolumeUUIDKey as String]).flatMap { value -> String? in
            guard CFGetTypeID(value as CFTypeRef) == CFUUIDGetTypeID() else { return nil }
            return CFUUIDCreateString(nil, (value as! CFUUID)) as String?
        }
        return DiskFacts(
            volumeName: value(kDADiskDescriptionVolumeNameKey),
            volumeUUID: uuid,
            ejectable: value(kDADiskDescriptionMediaEjectableKey) ?? false,
            removable: value(kDADiskDescriptionMediaRemovableKey) ?? false,
            isInternal: value(kDADiskDescriptionDeviceInternalKey),
            model: (value(kDADiskDescriptionDeviceModelKey) as String?)?.trimmingCharacters(in: .whitespaces),
            connection: value(kDADiskDescriptionDeviceProtocolKey),
            wholeDisk: whole,
            physicalDisk: whole.flatMap(physicalDisk)
        )
    }

    /// The physical disk under a disk. An APFS container is a disk of its own on top of the
    /// physical one, and ejecting the container only unmounts it: a disk image stays attached and
    /// a drive stays connected. Finder ejects the physical disk, found here by walking up the
    /// I/O Registry to the outermost whole disk.
    static func physicalDisk(of bsdName: String) -> String? {
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var parents: io_iterator_t = 0
        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        guard IORegistryEntryCreateIterator(service, kIOServicePlane, options, &parents) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(parents) }
        var outermost: String?
        while true {
            let entry = IOIteratorNext(parents)
            guard entry != 0 else { break }
            defer { IOObjectRelease(entry) }
            guard IOObjectConformsTo(entry, "IOMedia") != 0 else { continue }
            let whole = IORegistryEntryCreateCFProperty(entry, "Whole" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
            let name = IORegistryEntryCreateCFProperty(entry, "BSD Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            if whole == true, let name { outermost = name }
        }
        return outermost
    }

    /// A C string inside a fixed-size array in a struct, which Swift sees as a tuple.
    static func string<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { bytes in
            let characters = bytes.bindMemory(to: CChar.self)
            let end = characters.firstIndex(of: 0) ?? characters.count
            return String(decoding: bytes.prefix(end), as: UTF8.self)
        }
    }
}
