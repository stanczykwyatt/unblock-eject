// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UnblockEject",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "UnblockEject", targets: ["UnblockEject"]),
        .executable(name: "unblock-eject", targets: ["UnblockEjectCLI"]),
    ],
    targets: [
        // Finding the disks you can eject, asking macOS which processes have files open on them,
        // naming those processes in plain words, and ejecting, with nothing tied to the app's
        // windows, so it can be tested with made-up processes and a scratch disk image.
        .target(name: "EjectCore"),
        .executableTarget(name: "UnblockEject", dependencies: ["EjectCore"]),
        .executableTarget(name: "UnblockEjectCLI", dependencies: ["EjectCore"]),
        .testTarget(name: "EjectCoreTests", dependencies: ["EjectCore"]),
        // The app's glue, tested with made-up disks and apps, and windows that are never shown.
        .testTarget(name: "UnblockEjectTests", dependencies: ["UnblockEject", "EjectCore"]),
    ]
)
