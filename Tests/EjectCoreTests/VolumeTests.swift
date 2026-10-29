import Testing
@testable import EjectCore

@Suite("Volumes")
struct VolumeTests {
    private func mount(_ path: String, _ device: String = "disk6s1", hidden: Bool = false) -> MountEntry {
        MountEntry(path: path, source: "/dev/\(device)", fileSystem: "apfs", isHidden: hidden, size: 1000)
    }

    @Test func externalDrivesCardsAndDiskImagesAreListed() throws {
        let drive = try #require(VolumeFilter.volume(
            for: mount("/Volumes/Travel SSD"),
            facts: DiskFacts(volumeName: "Travel SSD", ejectable: true, isInternal: false, model: "Portable SSD", connection: "USB", wholeDisk: "disk6")
        ))
        #expect(drive.kind == .externalDrive && drive.name == "Travel SSD" && drive.wholeDisk == "disk6" && drive.device == "disk6s1")
        #expect(drive.size == 1000)

        let card = try #require(VolumeFilter.volume(for: mount("/Volumes/CARD", "disk7s1"), facts: DiskFacts(ejectable: true, removable: true, connection: "Secure Digital")))
        #expect(card.kind == .memoryCard && card.name == "CARD" && card.wholeDisk == "disk7")

        let image = try #require(VolumeFilter.volume(for: mount("/Volumes/Brushwork", "disk8s1"), facts: DiskFacts(ejectable: true, removable: true, model: "Disk Image", connection: "Virtual Interface")))
        #expect(image.kind == .diskImage)
    }

    @Test func aDriveThatOnlySaysItsExternalCounts() throws {
        // Some USB drives say they're neither ejectable nor removable, only not internal.
        let volume = try #require(VolumeFilter.volume(for: mount("/Volumes/Old Backup"), facts: DiskFacts(isInternal: false)))
        #expect(volume.kind == .externalDrive)
    }

    @Test func theStartupDiskAndSystemVolumesNeverAre() {
        let builtIn = DiskFacts(volumeName: "Macintosh HD", isInternal: true, model: "APPLE SSD")
        #expect(VolumeFilter.volume(for: mount("/", "disk3s1s1"), facts: builtIn) == nil)
        #expect(VolumeFilter.volume(for: mount("/System/Volumes/Data", "disk3s5", hidden: true), facts: builtIn, includeHidden: true) == nil)
        #expect(VolumeFilter.volume(for: mount("/System/Volumes/Data", "disk3s5"), facts: DiskFacts(ejectable: true), includeHidden: true) == nil)
        // A second internal disk you can't eject.
        #expect(VolumeFilter.volume(for: mount("/Volumes/Spare", "disk4s1"), facts: builtIn) == nil)
    }

    @Test func thingsThatArentDisksNeverAre() {
        let facts = DiskFacts(ejectable: true)
        #expect(VolumeFilter.volume(for: MountEntry(path: "/dev", source: "devfs", fileSystem: "devfs"), facts: facts) == nil)
        #expect(VolumeFilter.volume(for: MountEntry(path: "/System/Volumes/Data/home", source: "map auto_home", fileSystem: "autofs"), facts: facts) == nil)
        #expect(VolumeFilter.volume(for: MountEntry(path: "/Volumes/share", source: "//me@server/share", fileSystem: "smbfs"), facts: facts) == nil)
        #expect(VolumeFilter.volume(for: mount("/Volumes/X"), facts: nil) == nil)
    }

    @Test func hiddenVolumesOnlyWhenAsked() {
        let facts = DiskFacts(ejectable: true, model: "Disk Image")
        let entry = mount("/Library/Developer/CoreSimulator/Volumes/iOS_22A", "disk9s1", hidden: true)
        #expect(VolumeFilter.volume(for: entry, facts: facts) == nil)
        #expect(VolumeFilter.volume(for: entry, facts: facts, includeHidden: true)?.isHidden == true)
    }

    @Test func anEmptyNameFallsBackToTheFolder() {
        let volume = VolumeFilter.volume(for: mount("/Volumes/Untitled"), facts: DiskFacts(volumeName: "", ejectable: true))
        #expect(volume?.name == "Untitled")
    }

    @Test(arguments: [("disk5s1", "disk5"), ("disk12s3s1", "disk12"), ("disk5", "disk5"), ("disk", "disk"), ("weird", "weird")])
    func wholeDisks(device: String, whole: String) {
        #expect(VolumeFilter.wholeDisk(of: device) == whole)
    }

    @Test func volumesOnOneDiskEjectTogether() {
        let drives = Drive.group([Sample.travel, Sample.backupA, Sample.card, Sample.backupB])
        #expect(drives.map(\.wholeDisk) == ["disk6", "disk10", "disk7"])
        #expect(drives[1].name == "Archive and Archive 2")
        #expect(drives[1].mountPoints == ["/Volumes/Archive", "/Volumes/Archive 2"])
        #expect(Drive(wholeDisk: "disk1", volumes: [Sample.travel, Sample.card, Sample.installer]).name == "Travel SSD, FIELD REC and Brushwork")
        #expect(Drive(wholeDisk: "disk1", volumes: []).name == "disk1")
    }

    @Test func pathsAreMatchedByWholeFolders() {
        #expect(Sample.travel.contains("/Volumes/Travel SSD"))
        #expect(Sample.travel.contains("/Volumes/Travel SSD/Photos/a.raw"))
        #expect(!Sample.travel.contains("/Volumes/Travel SSD 2/a.raw"))
        #expect(!Sample.travel.contains("/Volumes/Travel"))
        #expect(Paths.isInside("/a/b", "/a/"))
        #expect(Paths.isInside("/anything", "/"))
        // "Archive" and "Archive 2" are different volumes, even though one name starts the other.
        #expect(Sample.archiveDrive.volume(containing: "/Volumes/Archive 2/x")?.name == "Archive 2")
        #expect(Sample.archiveDrive.volume(containing: "/Volumes/Archive/x")?.name == "Archive")
        #expect(Sample.archiveDrive.volume(containing: "/Volumes/Other") == nil)
    }

    @Test func aVolumeMountedInsideAnotherBelongsToTheInnerOne() {
        let outer = Volume(path: "/Volumes/Outer", name: "Outer", device: "disk6s1", wholeDisk: "disk6", kind: .externalDrive)
        let inner = Volume(path: "/Volumes/Outer/Inner", name: "Inner", device: "disk6s2", wholeDisk: "disk6", kind: .externalDrive)
        let drive = Drive(wholeDisk: "disk6", volumes: [outer, inner])
        #expect(drive.volume(containing: "/Volumes/Outer/Inner/file")?.name == "Inner")
    }

    @Test func hiddenVolumesAreCheckedButNotNamed() {
        let shown = Sample.backupA
        let hidden = Volume(path: "/Volumes/.snapshots", name: "Snapshots", device: "disk10s3", wholeDisk: "disk10", kind: .externalDrive, size: 99, isHidden: true)
        let drive = Drive(wholeDisk: "disk10", volumes: [shown, hidden])
        #expect(drive.name == "Archive" && drive.isShown && drive.mountPoints.count == 2)
        #expect(Describe.details(drive) == "External drive")
        #expect(!Drive(wholeDisk: "disk9", volumes: [Sample.hidden]).isShown)
        #expect(Drive(wholeDisk: "disk9", volumes: [Sample.hidden]).name == "Scratch")
    }

    @Test func translocatedAppsMapBackToTheirDisk() {
        let mounts = [
            MountEntry(path: "/private/var/folders/xy/T/AppTranslocation/1234/d", source: "/Volumes/Brushwork/Brushwork Installer.app", fileSystem: "nullfs"),
            MountEntry(path: "/private/var/folders/xy/T/AppTranslocation/5678/d", source: "/Volumes/Other/Thing.app", fileSystem: "nullfs"),
            MountEntry(path: "/Volumes/Brushwork", source: "/dev/disk8s1", fileSystem: "apfs"),
        ]
        let found = MountTable.translocations(inside: ["/Volumes/Brushwork"], mounts: mounts)
        #expect(found.map(\.path) == ["/private/var/folders/xy/T/AppTranslocation/1234/d"])
        #expect(found.map(\.source) == ["/Volumes/Brushwork/Brushwork Installer.app"])
    }

    @Test func diskFactsCarryTheVolumeID() throws {
        let volume = try #require(VolumeFilter.volume(for: mount("/Volumes/X"), facts: DiskFacts(volumeUUID: "ABC", ejectable: true)))
        #expect(volume.uuid == "ABC")
    }
}
