import DiskArbitration
import Foundation

/// How an eject went.
public enum EjectResult: Hashable, Sendable {
    case ejected
    /// Something still had files open. `message` is what the process that refused said, if anything.
    case busy(message: String?)
    case notAllowed
    /// It was already gone.
    case gone
    case failed(code: Int32)
    /// macOS didn't answer in time.
    case timedOut

    /// Reads Disk Arbitration's status code. Busy comes back either as its own code or as the
    /// `EBUSY` error from unmounting, wrapped in Disk Arbitration's Unix error range.
    public static func from(status: Int32, message: String? = nil) -> EjectResult {
        let code = UInt32(bitPattern: status)
        if status == 0 { return .ejected }
        if code == UInt32(truncatingIfNeeded: kDAReturnBusy) || code == UInt32(truncatingIfNeeded: kDAReturnExclusiveAccess) { return .busy(message: message) }
        if code == UInt32(truncatingIfNeeded: kDAReturnNotPermitted) || code == UInt32(truncatingIfNeeded: kDAReturnNotPrivileged) { return .notAllowed }
        if code == UInt32(truncatingIfNeeded: kDAReturnNotMounted) || code == UInt32(truncatingIfNeeded: kDAReturnNotFound) { return .gone }
        if code & 0xFFFF_C000 == 0xC000 {
            switch Int32(code & 0x3FFF) {
            case EBUSY: return .busy(message: message)
            case EPERM, EACCES: return .notAllowed
            case ENOENT, ENODEV, ENXIO: return .gone
            default: break
            }
        }
        return .failed(code: status)
    }
}

/// Ejects a disk.
public protocol Ejecting: Sendable {
    func eject(_ drive: Drive) async -> EjectResult
}

/// Ejects through Disk Arbitration, as Finder does: every volume on the disk is unmounted, then
/// the disk is ejected. It never forces anything, so if any app still has a file open, macOS
/// refuses. On a disk with more than one container or partition, ones that weren't in use may
/// already be unmounted by then, as with Finder.
public struct DiskEjector: Ejecting {
    public init() {}

    public func eject(_ drive: Drive) async -> EjectResult {
        let queue = DispatchQueue(label: "com.stanczykwyatt.UnblockEject.eject")
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return .failed(code: -1) }
        DASessionSetDispatchQueue(session, queue)
        defer { DASessionSetDispatchQueue(session, nil) }
        // A disk that was ejected a moment ago can still be found by name, but has no description.
        guard let whole = DADiskCreateFromBSDName(kCFAllocatorDefault, session, drive.wholeDisk), DADiskCopyDescription(whole) != nil else { return .gone }

        // The same disk as listed: a disk plugged in since can get the same name.
        guard drive.volumes.allSatisfy({ Self.isStillMounted($0, session: session) }) else { return .gone }

        // APFS containers first, which takes every volume in them, then anything else on the disk.
        var disks: [DADisk] = []
        for container in Set(drive.volumes.map(\.container)).sorted() where container != drive.wholeDisk {
            if let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, container), DADiskCopyDescription(disk) != nil {
                disks.append(disk)
            }
        }
        disks.append(whole)
        for disk in disks {
            let unmounted = await Self.run { context in
                DADiskUnmount(disk, DADiskUnmountOptions(kDADiskUnmountOptionWhole), Self.done, context)
            }
            guard unmounted == .ejected else { return unmounted }
        }
        let ejected = await Self.run { context in
            DADiskEject(whole, DADiskEjectOptions(kDADiskEjectOptionDefault), Self.done, context)
        }
        // Once unmounted, a disk that's gone already is as good as ejected.
        return ejected == .gone ? .ejected : ejected
    }

    /// Whether a volume is still mounted where it was, with the same ID.
    static func isStillMounted(_ volume: Volume, session: DASession) -> Bool {
        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, volume.device),
              let description = DADiskCopyDescription(disk) as? [String: Any],
              let url = description[kDADiskDescriptionVolumePathKey as String] as? URL,
              url.standardizedFileURL.path == URL(fileURLWithPath: volume.path).standardizedFileURL.path else { return false }
        guard let uuid = volume.uuid else { return true }
        guard let current = description[kDADiskDescriptionVolumeUUIDKey as String],
              CFGetTypeID(current as CFTypeRef) == CFUUIDGetTypeID() else { return false }
        return CFUUIDCreateString(nil, (current as! CFUUID)) as String == uuid
    }

    /// How long to wait for macOS to answer, so a disk never stays "Ejecting…" for good.
    static let timeout: TimeInterval = 90

    /// Hands back the first answer, from Disk Arbitration or the timeout, and ignores the other.
    private final class Waiter: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<EjectResult, Never>?
        init(_ continuation: CheckedContinuation<EjectResult, Never>) { self.continuation = continuation }

        func finish(_ result: EjectResult) {
            lock.lock()
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(returning: result)
        }
    }

    private static func run(_ start: (UnsafeMutableRawPointer) -> Void) async -> EjectResult {
        await withCheckedContinuation { continuation in
            let waiter = Waiter(continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { waiter.finish(.timedOut) }
            start(Unmanaged.passRetained(waiter).toOpaque())
        }
    }

    /// Called once by Disk Arbitration when an unmount or eject finishes.
    private static let done: DADiskEjectCallback = { _, dissenter, context in
        guard let context else { return }
        let waiter = Unmanaged<Waiter>.fromOpaque(context).takeRetainedValue()
        guard let dissenter else {
            waiter.finish(.ejected)
            return
        }
        let message = DADissenterGetStatusString(dissenter) as String?
        waiter.finish(EjectResult.from(status: DADissenterGetStatus(dissenter), message: message))
    }
}
