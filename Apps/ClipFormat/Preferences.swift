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
    }

    private let defaults: UserDefaults

    @Published var indentWidth: Int {
        didSet { defaults.set(indentWidth, forKey: Key.indent) }
    }

    /// When off, the status item shows plain braces with no ✓/✕ state.
    @Published var showBadge: Bool {
        didSet { defaults.set(showBadge, forKey: Key.showBadge) }
    }

    /// Mirrors `SMAppService.mainApp` — the service, not a defaults key, is the
    /// source of truth, so a login item removed in System Settings shows up here.
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            applyLaunchAtLogin()
        }
    }

    /// Why the last toggle failed, if it did. Registration needs a signed app
    /// that LaunchServices knows about, which a bare Xcode build is not.
    @Published private(set) var launchAtLoginError: String?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.indent: 2, Key.showBadge: true])
        indentWidth = defaults.integer(forKey: Key.indent)
        showBadge = defaults.bool(forKey: Key.showBadge)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Picks up changes made outside the app (System Settings → Login Items).
    func refreshLaunchAtLoginStatus() {
        let enabled = SMAppService.mainApp.status == .enabled
        guard enabled != launchAtLogin else { return }
        launchAtLogin = enabled
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            NSLog("ClipFormat: launch at login change failed — \(error.localizedDescription)")
            launchAtLoginError = Self.explain(error)
            // Snap the toggle back to what the system actually thinks.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    /// `SMAppService` errors are terse ("Operation not permitted") and the usual
    /// cause is specific enough to name.
    private static func explain(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.code == 1 || nsError.domain == NSPOSIXErrorDomain {
            return "macOS wouldn’t register ClipFormat. Move it to /Applications, "
                + "reopen it from there, and try again — login items need a signed "
                + "app in a stable location."
        }
        return nsError.localizedDescription
    }
}
