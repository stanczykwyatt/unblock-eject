import AppKit
import EjectCore

/// Quitting apps. The app delegate quits real ones; tests record what would have been quit.
@MainActor
protocol AppControl: AnyObject {
    /// Asks an app to quit, and says whether it was asked.
    func quit(_ app: AppFacts) -> Bool
}

@MainActor
final class WorkspaceApps: AppControl {
    func quit(_ app: AppFacts) -> Bool {
        // Only the same app that was listed: a process ID can be reused by another app after the
        // first one quits, so its location, ID and start time must all still match.
        guard let path = app.bundlePath, let running = NSRunningApplication(processIdentifier: app.pid), !running.isTerminated,
              running.bundleURL?.path == path, running.bundleIdentifier == app.bundleID, running.launchDate == app.launchDate,
              running.processIdentifier != getpid() else { return false }
        // A normal quit, the same as choosing Quit from the app's own menu. The app can ask to save
        // your work first, or say no. Nothing is ever force-quit.
        return running.terminate()
    }
}
