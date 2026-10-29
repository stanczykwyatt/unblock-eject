import Foundation

/// Settings, kept in the app's own preferences file.
struct Preferences {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let launchedBefore = "launchedBefore"
    }

    var launchedBefore: Bool {
        get { defaults.bool(forKey: Key.launchedBefore) }
        nonmutating set { defaults.set(newValue, forKey: Key.launchedBefore) }
    }
}
