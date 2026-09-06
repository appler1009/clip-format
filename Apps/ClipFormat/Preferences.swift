import ClipFormatShared
import Foundation
import ServiceManagement
import SwiftUI

/// User settings, stored in the App Group suite so Quick Look can read them.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    static let minFontSize = AppGroup.minFontSize
    static let maxFontSize = AppGroup.maxFontSize
    static let defaultFontSize = AppGroup.defaultFontSize

    private enum Key {
        static let indent = AppGroup.Key.indentWidth
        static let showBadge = AppGroup.Key.showBadge
        static let fontSize = AppGroup.Key.fontSize
    }

    private let defaults: UserDefaults

    @Published var indentWidth: Int {
        didSet { defaults.set(indentWidth, forKey: Key.indent) }
    }

    /// When off, the status item shows plain braces with no ✓/✕ state.
    @Published var showBadge: Bool {
        didSet { defaults.set(showBadge, forKey: Key.showBadge) }
    }

    /// Point size of the formatted JSON in the popover. ⌘+ / ⌘− nudge it.
    @Published var fontSize: Int {
        didSet {
            let clamped = min(Self.maxFontSize, max(Self.minFontSize, fontSize))
            if clamped != fontSize {
                fontSize = clamped
                return
            }
            defaults.set(fontSize, forKey: Key.fontSize)
        }
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

    private init(defaults: UserDefaults = AppGroup.defaults) {
        Self.migrateStandardDefaultsIfNeeded(to: defaults)
        self.defaults = defaults
        defaults.register(defaults: [
            Key.indent: AppGroup.defaultIndentWidth,
            Key.showBadge: true,
            Key.fontSize: Self.defaultFontSize,
        ])
        indentWidth = defaults.integer(forKey: Key.indent)
        showBadge = defaults.bool(forKey: Key.showBadge)
        fontSize = defaults.integer(forKey: Key.fontSize)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Copies indent / font / badge out of the old per-app defaults so a
    /// first launch after the App Group lands does not reset them.
    private static func migrateStandardDefaultsIfNeeded(to suite: UserDefaults) {
        let standard = UserDefaults.standard
        guard suite !== standard else { return }
        guard suite.object(forKey: Key.indent) == nil else { return }
        if standard.object(forKey: Key.indent) != nil {
            suite.set(standard.integer(forKey: Key.indent), forKey: Key.indent)
        }
        if standard.object(forKey: Key.fontSize) != nil {
            suite.set(standard.integer(forKey: Key.fontSize), forKey: Key.fontSize)
        }
        if standard.object(forKey: Key.showBadge) != nil {
            suite.set(standard.bool(forKey: Key.showBadge), forKey: Key.showBadge)
        }
    }

    func increaseFontSize() {
        fontSize = min(Self.maxFontSize, fontSize + 1)
    }

    func decreaseFontSize() {
        fontSize = max(Self.minFontSize, fontSize - 1)
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
            Diagnostics.error("launch at login change failed", ["error": error.localizedDescription])
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
