import EjectCore
import Foundation

let status = MainActor.assumeIsolated {
    Command.run(
        Array(CommandLine.arguments.dropFirst()),
        workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        apps: { RunningApps.snapshot() },
        out: { print($0) },
        err: { fputs($0 + "\n", stderr) }
    )
}
exit(status)
