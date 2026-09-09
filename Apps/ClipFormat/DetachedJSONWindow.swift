import AppKit

/// The window an `NSPopover` tears off into.
///
/// AppKit only supplies the gesture and the window chrome. It offers to move
/// the popover's own view in here, but a SwiftUI hosting view arrives from that
/// transplant without its sizing and draws nothing, so this window is vended
/// empty and `detachableWindow(for:)` gives it its own controller over the same
/// `ClipboardMonitor`. Do not "simplify" it back to inheriting the popover's
/// view — that is the blank-window bug.
///
/// Actions sit in the SwiftUI chrome (same cluster as the popover). Content
/// uses a full-size title bar so the window still gets traffic lights and a
/// drag region without an NSToolbar of its own.
@MainActor
final class DetachedJSONWindow: NSWindow {
    /// Written at commit points — the end of a live resize, the start of a
    /// full-screen transition, close and quit — and applied only when one
    /// exists, so the tear-off gesture places a first-ever window itself.
    static let frameName = NSWindow.FrameAutosaveName("ClipFormatDetachedJSON")

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "ClipFormat"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        minSize = NSSize(width: 420, height: 220)
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

    /// True from the start of the enter-full-screen animation until the exit
    /// has finished. `styleMask` is not a reliable signal for this: it does not
    /// necessarily carry `.fullScreen` while AppKit is growing the window
    /// toward the display, so the animation's intermediate frames would be
    /// saved as if the user had resized to nearly the screen.
    private var isFullScreenOrTransitioning = false

    /// Remembers the frame, unless the window is full screen or on its way —
    /// where `frame` is (or is becoming) the whole display, and restoring that
    /// next time would open a torn-off window the size of the screen.
    func persistFrameUnlessFullScreen() {
        guard !isFullScreenOrTransitioning else { return }
        saveFrame(usingName: Self.frameName)
    }

    /// Snapshots the windowed frame before AppKit starts growing it.
    func willEnterFullScreen() {
        persistFrameUnlessFullScreen()
        isFullScreenOrTransitioning = true
    }

    func didExitFullScreen() {
        isFullScreenOrTransitioning = false
    }
}
