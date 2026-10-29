import Darwin
import Foundation

/// A running process, as the kernel describes it.
public struct ProcessFacts: Hashable, Sendable, Codable {
    public let pid: Int32
    public let parent: Int32
    public let name: String
    /// The program it's running, if macOS said.
    public let executable: String?

    public init(pid: Int32, parent: Int32, name: String, executable: String?) {
        self.pid = pid
        self.parent = parent
        self.name = name
        self.executable = executable
    }
}

/// Something a process has open on a disk, which keeps the disk from ejecting.
public struct OpenFile: Hashable, Sendable, Comparable, Codable {
    public enum Use: String, Hashable, Sendable, Codable, Comparable {
        /// The program itself is on the disk, like an app opened straight from a disk image.
        case program
        /// An open file.
        case file
        /// The folder a process is working in, like a terminal that's `cd`'d into the disk.
        case folder
        /// A file loaded into memory, like a plug-in or library on the disk.
        case loaded
        /// Something the kernel says is open on the disk but can't give a path for, like a file
        /// deleted while it was open.
        case unnamed

        private var order: Int {
            switch self {
            case .program: 0
            case .file: 1
            case .folder: 2
            case .loaded: 3
            case .unnamed: 4
            }
        }

        public static func < (a: Use, b: Use) -> Bool { a.order < b.order }
    }

    public let path: String
    public let use: Use

    public init(path: String, use: Use) {
        self.path = path
        self.use = use
    }

    public static func < (a: OpenFile, b: OpenFile) -> Bool {
        a.use != b.use ? a.use < b.use : a.path.localizedStandardCompare(b.path) == .orderedAscending
    }
}

/// A process and what it has open on the disk being checked.
public struct ProcessUse: Hashable, Sendable {
    public let process: ProcessFacts
    public let files: [OpenFile]

    public init(process: ProcessFacts, files: [OpenFile]) {
        self.process = process
        self.files = files
    }
}

/// Where the list of processes comes from: the kernel in the app, made-up processes in tests.
public protocol ProcessSource: Sendable {
    /// Your processes with anything open on these volumes.
    func uses(of mountPoints: [String]) -> [ProcessUse]
    func process(_ pid: Int32) -> ProcessFacts?
}

/// Asks the kernel, through libproc, which of your processes have files open on a volume. This is
/// what `lsof` does. It reads only file names and process names, never what's in a file, and
/// macOS only answers for processes running as you: those of other users and of macOS itself,
/// like Spotlight's indexer and Time Machine, are hidden from it.
public struct LiveProcesses: ProcessSource {
    public init() {}

    public func uses(of mountPoints: [String]) -> [ProcessUse] {
        var places = mountPoints.map { Place(path: $0, shownAs: $0, fileSystem: Self.fileSystem(of: $0)) }
        // Apps opened from a downloaded disk image run from a copy macOS mounts elsewhere.
        for copy in MountTable.translocations(inside: mountPoints, mounts: MountTable.mounts()) {
            places.append(Place(path: copy.path, shownAs: copy.source, fileSystem: Self.fileSystem(of: copy.path)))
        }
        var pids = Set<Int32>()
        for place in places {
            pids.formUnion(Self.pids(onVolume: place.path))
        }
        return pids.sorted().compactMap { pid in
            guard let process = process(pid), let first = mountPoints.first else { return nil }
            var files = Self.files(of: pid, on: places)
            // The kernel found something, like a file deleted while open, that has no path to show.
            if files.isEmpty { files = [OpenFile(path: first, use: .unnamed)] }
            return ProcessUse(process: process, files: files)
        }
    }

    public func process(_ pid: Int32) -> ProcessFacts? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        let executable = Self.executable(of: pid)
        var name = executable.map { ($0 as NSString).lastPathComponent } ?? ""
        if name.isEmpty {
            var buffer = [CChar](repeating: 0, count: 256)
            proc_name(pid, &buffer, UInt32(buffer.count))
            name = Self.string(buffer)
        }
        if name.isEmpty { name = MountTable.string(info.pbsi_comm) }
        return ProcessFacts(pid: pid, parent: Int32(bitPattern: info.pbsi_ppid), name: name, executable: executable)
    }

    /// A volume to look on: where it's mounted, the file system ID the kernel tags its files with,
    /// and the path to show for it.
    struct Place {
        let path: String
        let shownAs: String
        let fileSystem: fsid_t?

        /// Whether a file belongs here: by file system ID when the kernel gives one, which also
        /// keeps files on a volume mounted inside another apart, or else by path.
        func holds(_ path: String, fileSystem id: fsid_t?) -> Bool {
            if let id, let fileSystem, id.val != (0, 0) { return id.val == fileSystem.val }
            return Paths.isInside(path, self.path)
        }

        /// The path as you'd find it, on the disk rather than in macOS's copy of it.
        func shown(_ path: String) -> String {
            guard shownAs != self.path, Paths.isInside(path, self.path) else { return path }
            return shownAs + path.dropFirst(self.path.count)
        }
    }

    static func fileSystem(of path: String) -> fsid_t? {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }
        return info.f_fsid
    }

    /// Processes with anything on the volume open, as their working folder or loaded into memory.
    /// Files opened only to watch for changes, as the Dock and file watchers do, don't stop an
    /// eject, so they're left out.
    static func pids(onVolume mountPoint: String) -> [Int32] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return [] }
        // Room for processes started since the count.
        var buffer = [Int32](repeating: 0, count: Int(needed) / MemoryLayout<Int32>.size + 256)
        let bytes = proc_listpidspath(
            UInt32(PROC_ALL_PIDS), 0, mountPoint, UInt32(PROC_LISTPIDSPATH_PATH_IS_VOLUME | PROC_LISTPIDSPATH_EXCLUDE_EVTONLY),
            &buffer, Int32(buffer.count * MemoryLayout<Int32>.size)
        )
        guard bytes > 0 else { return [] }
        return Array(buffer.prefix(Int(bytes) / MemoryLayout<Int32>.size)).filter { $0 > 0 }
    }

    /// What one process has open under these folders, matched by path.
    public static func files(of pid: Int32, under folders: [String]) -> [OpenFile] {
        files(of: pid, on: folders.map { Place(path: $0, shownAs: $0, fileSystem: nil) })
    }

    /// What one process has open on these volumes: its program, open files, working folder and,
    /// if none of those, anything it has loaded into memory from there.
    static func files(of pid: Int32, on places: [Place]) -> [OpenFile] {
        func shown(_ path: String, _ id: fsid_t?) -> String? {
            places.first { $0.holds(path, fileSystem: id) }.map { $0.shown(path) }
        }
        var found = Set<OpenFile>()
        let executable = executable(of: pid)
        if let executable, let path = shown(executable, nil) {
            found.insert(OpenFile(path: path, use: .program))
        }
        for file in openFiles(of: pid) {
            if let path = shown(file.path, file.fileSystem) { found.insert(OpenFile(path: path, use: .file)) }
        }
        var paths = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        if proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &paths, size) == size {
            for folder in [paths.pvi_cdir, paths.pvi_rdir] {
                let path = MountTable.string(folder.vip_path)
                guard !path.isEmpty, let place = shown(path, folder.vip_vi.vi_fsid) else { continue }
                found.insert(OpenFile(path: place, use: .folder))
            }
        }
        if found.isEmpty {
            for file in loadedFiles(of: pid) where file.path != executable {
                if let path = shown(file.path, file.fileSystem) { found.insert(OpenFile(path: path, use: .loaded)) }
            }
        }
        return found.sorted()
    }

    static func executable(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return string(buffer)
    }

    static func string(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    struct VnodeFile: Hashable {
        let path: String
        let fileSystem: fsid_t

        static func == (a: VnodeFile, b: VnodeFile) -> Bool { a.path == b.path && a.fileSystem.val == b.fileSystem.val }
        func hash(into hasher: inout Hasher) { hasher.combine(path) }
    }

    /// Open files, leaving out the ones opened only to watch for changes.
    static func openFiles(of pid: Int32) -> [VnodeFile] {
        let stride = MemoryLayout<proc_fdinfo>.stride
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0 else { return [] }
        // Room for files opened since the count.
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride + 32)
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, Int32(descriptors.count * stride))
        guard bytes > 0 else { return [] }
        var files: [VnodeFile] = []
        for descriptor in descriptors.prefix(Int(bytes) / stride) where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
            var info = vnode_fdinfowithpath()
            let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, size) == size,
                  info.pfi.fi_openflags & UInt32(O_EVTONLY) == 0 else { continue }
            let path = MountTable.string(info.pvip.vip_path)
            files.append(VnodeFile(path: path, fileSystem: info.pvip.vip_vi.vi_fsid))
        }
        return files
    }

    /// Files mapped into the process's memory, walking its memory regions one by one.
    static func loadedFiles(of pid: Int32) -> Set<VnodeFile> {
        var files = Set<VnodeFile>()
        var address: UInt64 = 0
        let size = Int32(MemoryLayout<proc_regionwithpathinfo>.size)
        // A ceiling, so a process changing its memory as it's walked can't keep this going.
        for _ in 0..<200_000 {
            var region = proc_regionwithpathinfo()
            guard proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, address, &region, size) == size else { break }
            let path = MountTable.string(region.prp_vip.vip_path)
            if !path.isEmpty { files.insert(VnodeFile(path: path, fileSystem: region.prp_vip.vip_vi.vi_fsid)) }
            let next = region.prp_prinfo.pri_address &+ region.prp_prinfo.pri_size
            guard next > address else { break }
            address = next
        }
        return files
    }
}
