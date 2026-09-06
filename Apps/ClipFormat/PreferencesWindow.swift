import AppKit
import SwiftUI

/// Hosts `PreferencesView` in a window the app owns.
///
/// SwiftUI's `Settings` scene is reached through `showSettingsWindow:`, a
/// private selector whose name has changed across releases and which does
/// nothing at all here. An agent app has no menu bar to open Settings from
/// either, so owning the window is both simpler and more predictable.
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
