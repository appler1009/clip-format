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
        // A JSON payload is worth reading at full width, so the green button
        // offers full screen rather than only zoom.
        collectionBehavior = [.fullScreenPrimary, .participatesInCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Escape closes it, matching the popover it was torn from — except in
    /// full screen, where Escape is how you leave full screen and closing the
    /// window out from under that is jarring.
    override func cancelOperation(_ sender: Any?) {
        guard !styleMask.contains(.fullScreen) else {
            toggleFullScreen(nil)
            return
        }
        close()
    }

    /// Remembers the frame, unless the window is in full screen — where
    /// `frame` is the whole display, and restoring that next time would open a
    /// torn-off window the size of the screen.
    func persistFrameUnlessFullScreen() {
        guard !styleMask.contains(.fullScreen) else { return }
        saveFrame(usingName: Self.frameName)
    }
}
