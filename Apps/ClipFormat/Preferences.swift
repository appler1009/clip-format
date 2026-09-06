import Foundation
import ServiceManagement
import SwiftUI

/// User settings, stored in `UserDefaults` and observed by the whole app.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let indent = "indentWidth"
        static let showBadge = "showBadge"
        static let launchAtLogin = "launchAtLogin"
    }

    private let defaults: UserDefaults

    @Published var indentWidth: Int {
        didSet { defaults.set(indentWidth, forKey: Key.indent) }
    }

    /// When off, the status item shows plain braces with no ✓/✕ state.
    @Published var showBadge: Bool {
        didSet { defaults.set(showBadge, forKey: Key.showBadge) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            applyLaunchAtLogin()
        }
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.indent: 2, Key.showBadge: true])
        indentWidth = defaults.integer(forKey: Key.indent)
        showBadge = defaults.bool(forKey: Key.showBadge)
        // The service's own state is the truth; our default is only a fallback
        // if the user has never touched the toggle.
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
        } catch {
            NSLog("ClipFormat: launch at login change failed — \(error.localizedDescription)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
