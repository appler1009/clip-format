import AppKit

/// The window an `NSPopover` tears off into.
///
/// AppKit only supplies the gesture and the window chrome. It offers to move
/// the popover's own view in here, but a SwiftUI hosting view arrives from that
/// transplant without its sizing and draws nothing, so this window is vended
/// empty and `detachableWindow(for:)` gives it its own controller over the same
/// `ClipboardMonitor`. Do not "simplify" it back to inheriting the popover's
/// view — that is the blank-window bug.
@MainActor
final class DetachedJSONWindow: NSWindow {
    /// Saved on close rather than continuously, and applied only when one
    /// exists, so the tear-off gesture places a first-ever window itself.
    static let frameName = NSWindow.FrameAutosaveName("ClipFormatDetachedJSON")

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            // No fullSizeContentView: the content would slide under the
            // traffic lights, and PopoverView's header is a compact row with
            // no inset of its own to clear them with.
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "Clipboard JSON"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 380, height: 220)
        collectionBehavior = [.fullScreenNone, .participatesInCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Escape closes it, matching the popover it was torn from.
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
