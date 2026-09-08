import AppKit

/// The window an `NSPopover` tears off into.
///
/// AppKit drives the gesture: the delegate says the popover may detach, this
/// window is handed back, and AppKit moves the popover's content view into it.
/// Nothing is copied, so the view keeps the `ClipboardMonitor` it was already
/// observing and the torn-off window goes on mirroring the clipboard.
@MainActor
final class DetachedJSONWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Clipboard JSON"
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        minSize = NSSize(width: 380, height: 220)
        // Restores where the user last put it, across launches.
        setFrameAutosaveName("ClipFormatDetachedJSON")
        // An agent app has no Window menu, so Escape is the way out that
        // matches the popover the window came from.
        collectionBehavior = [.fullScreenNone, .participatesInCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
