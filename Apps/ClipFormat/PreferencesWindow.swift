import AppKit
import SwiftUI

/// Hosts `PreferencesView` in a window the app owns.
///
/// SwiftUI requires a `Settings` scene for the app lifecycle, but that scene
/// is left empty here: `showSettingsWindow:` is unreliable in an agent app,
/// and ⌘, / the Settings menu item are redirected to this controller via
/// `CommandGroup(replacing: .appSettings)` in `ClipFormatApp`.
@MainActor
final class PreferencesWindowController {
    private var window: NSWindow?

    func show(preferences: Preferences) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: PreferencesView(preferences: preferences))
        let window = EscapableWindow(contentViewController: hosting)
        window.title = "ClipFormat Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// A titled window whose Escape key is Close, like a sheet or Preferences panel.
private final class EscapableWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
