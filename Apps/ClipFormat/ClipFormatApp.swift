import AppKit
import Combine
import SwiftUI

@main
struct ClipFormatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Satisfies the SwiftUI lifecycle; LSUIElement keeps the app out of the
        // Dock. Content stays empty on purpose — the real panel is
        // PreferencesWindowController. Replacing `.appSettings` so ⌘, and the
        // Settings menu item open that panel instead of this empty scene
        // (which shows up once a torn-off window makes the app key).
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") {
                        delegate.openPreferences()
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private let monitor = ClipboardMonitor()
    private let preferences = Preferences.shared
    private var cancellables: Set<AnyCancellable> = []
    private var eventMonitor: Any?
    private var keyMonitor: Any?
    private let preferencesWindow = PreferencesWindowController()
    /// Non-nil once the user has dragged the popover off the status item.
    private var detachedWindow: DetachedJSONWindow?
    /// Set when a tear-off spends the current popover; see the detach handler.
    private var popoverIsSpent = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configurePopover()

        // Re-render the icon whenever the clipboard state or the badge
        // preference changes. The published values have to come from the
        // stream: `@Published` fires in `willSet`, so reading the property
        // inside the sink would render the *previous* state.
        monitor.$document
            .map(\.isValid)
            .removeDuplicates()
            .combineLatest(preferences.$showBadge)
            .sink { [weak self] isValid, showBadge in
                self?.updateIcon(isValid: isValid, showBadge: showBadge)
            }
            .store(in: &cancellables)

        monitor.start()
        Diagnostics.info("launched", ["version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"])

        // QA hooks: `open ClipFormat.app --args --show-popover` (or
        // --show-preferences) brings the UI up without a click. A popover in an
        // agent app is not exposed to Accessibility, so this is the only way to
        // drive it from a script.
        if ProcessInfo.processInfo.arguments.contains("--show-preferences") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.openPreferences()
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--show-popover") {
            // The status button has no window yet at launch, so a popover
            // anchored to it would have nowhere to appear.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.togglePopover()
                guard let self else { return }
                Diagnostics.info("qa popover requested", [
                    "isShown": "\(self.popover.isShown)",
                    "contentSize": "\(self.popover.contentSize)",
                    "viewFrame": "\(self.popover.contentViewController?.view.frame ?? .zero)",
                    "popoverWindow": "\(String(describing: self.popover.contentViewController?.view.window?.frame))",
                ])
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Cheap changeCount check — do not force a re-parse of unchanged
        // clipboard contents every time the app becomes key.
        monitor.refresh()
        // The user may have removed us from Login Items while we were inactive.
        preferences.refreshLaunchAtLoginStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        removeDismissMonitor()
        // windowDidMove has no "ended" sibling, so a window that was dragged
        // and never resized is recorded here.
        detachedWindow?.persistFrameUnlessFullScreen()
    }

    // MARK: - Status item

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateIcon()
    }

    private func updateIcon(isValid: Bool? = nil, showBadge: Bool? = nil) {
        let showBadge = showBadge ?? preferences.showBadge
        let isValid = isValid ?? monitor.document.isValid
        let state: StatusItemIcon.State = showBadge ? (isValid ? .valid : .invalid) : .neutral
        statusItem?.button?.image = StatusItemIcon.image(for: state)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if isRightClick {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Clipboard", action: #selector(showJSONWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        menu.addItem(withTitle: "About ClipFormat", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClipFormat", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }

        // Attaching the menu to the status item would hijack left clicks, so
        // pop it manually and detach again immediately.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Popover

    /// One view, two hosts. Both get their own controller but the same
    /// `monitor`, so the popover and a torn-off window stay in step without
    /// anything being copied between them.
    private func makeContentController(chrome: PopoverChrome) -> NSHostingController<PopoverView> {
        NSHostingController(
            rootView: PopoverView(
                monitor: monitor,
                preferences: preferences,
                openPreferences: { [weak self] in self?.openPreferences() },
                chrome: chrome
            )
        )
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let hosting = makeContentController(chrome: .popover)
        // The view carries no fixed frame any more, so that the torn-off
        // window can resize it. That leaves the hosting controller reporting a
        // zero preferred size, which opens the popover invisibly, so the
        // popover's size is stated here instead.
        hosting.sizingOptions = []
        hosting.preferredContentSize = NSSize(width: 520, height: 420)
        hosting.view.autoresizingMask = [.width, .height]
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 520, height: 420)
    }

    /// One source, two hosts: the window shows its own controller over the
    /// same monitor, so a click on the status item while it is open should
    /// bring it forward rather than open a second copy of the same thing.
    private func focusDetachedWindow(_ window: DetachedJSONWindow) {
        monitor.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func togglePopover() {
        if let detachedWindow {
            focusDetachedWindow(detachedWindow)
            return
        }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        monitor.refresh()
        // Only a popover that has been torn off needs replacing; before that
        // the same instance shows content perfectly well, and rebuilding the
        // hosting tree on every click would be waste.
        if popoverIsSpent {
            popover = NSPopover()
            configurePopover()
            popoverIsSpent = false
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        installDismissMonitor()
    }

    /// `.transient` misses clicks in other apps' windows in an agent app, so we
    /// watch globally and close ourselves.
    private func installDismissMonitor() {
        removeDismissMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.popover.performClose(nil) }
        }
        installKeyMonitor()
    }

    /// ⌘+ / ⌘− for both surfaces. An agent app has no menu bar to hang the
    /// commands off, and the monitor has to outlive the popover because the
    /// torn-off window needs them too.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleFontSizeKey(event) ?? event
        }
    }

    private func removeDismissMonitor() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        // The key monitor stays while a torn-off window is around.
        guard detachedWindow == nil, let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func handleFontSizeKey(_ event: NSEvent) -> NSEvent? {
        guard popover.isShown || detachedWindow?.isKeyWindow == true else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.option),
              !flags.contains(.control) else { return event }
        switch event.charactersIgnoringModifiers {
        case "=", "+":
            preferences.increaseFontSize()
            return nil
        case "-", "_":
            preferences.decreaseFontSize()
            return nil
        default:
            return event
        }
    }

    // MARK: - Menu actions

    @objc private func showJSONWindow() {
        if let detachedWindow {
            focusDetachedWindow(detachedWindow)
        } else {
            togglePopover()
        }
    }

    @objc func openPreferences() {
        popover.performClose(nil)
        preferencesWindow.show(preferences: preferences)
    }

    @objc private func showAbout() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "ClipFormat",
            .init(rawValue: "Copyright"): "Revived.\nJSON and XML in the menu bar and in Quick Look.",
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Tear-off

/// Dragging the popover off the status item turns it into a window.
///
/// AppKit owns the gesture: we agree to it and hand back a window. The window
/// hosts its own copy of the view on the same `ClipboardMonitor`, so it keeps
/// mirroring the clipboard rather than freezing what was on screen when it was
/// torn off.
extension AppDelegate: NSPopoverDelegate {
    func popoverShouldDetach(_ popover: NSPopover) -> Bool { true }

    func detachableWindow(for popover: NSPopover) -> NSWindow? {
        if let detachedWindow { return detachedWindow }
        let window = DetachedJSONWindow()
        // AppKit hands the popover's view over, but a SwiftUI hosting view
        // arrives without its sizing and renders blank, so the window gets its
        // own controller on the same monitor instead.
        window.contentViewController = makeContentController(chrome: .window)
        // A window the user has sized before comes back the way they left it.
        // Only a first-ever tear-off needs a size stated, because the view
        // carries a minimum but no fixed size and would otherwise open at
        // 380x220 and clip the JSON. AppKit places it under the drag.
        if !window.setFrameUsingName(DetachedJSONWindow.frameName) {
            window.setContentSize(NSSize(width: 520, height: 420))
        }
        window.delegate = self
        detachedWindow = window

        // `popoverDidDetach` is never called when the delegate vends a window,
        // so the tidying up happens here — after this run loop turn, since
        // AppKit is still in the middle of the detach.
        //
        // The popover object itself has to be replaced. Once it has been
        // detached it opens blank forever after, even with fresh content, so
        // the next click gets a new one.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // A detached NSPopover cannot be reused: it opens blank from here
            // on, even given a new content controller, so the next open builds
            // a new one.
            self.popoverIsSpent = true
            // The global click monitor exists to close a transient popover; a
            // window is not transient, and leaving it installed would swallow
            // the first click in every other app.
            self.removeDismissMonitor()
            self.installKeyMonitor()
        }
        return window
    }
}

extension AppDelegate: NSWindowDelegate {
    // Commit points only. windowDidResize is the live-resize stream — one
    // UserDefaults write per pixel — and its frames during the full-screen
    // animation are on their way to the size of the display.
    func windowDidEndLiveResize(_ notification: Notification) {
        (notification.object as? DetachedJSONWindow)?.persistFrameUnlessFullScreen()
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        (notification.object as? DetachedJSONWindow)?.willEnterFullScreen()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        (notification.object as? DetachedJSONWindow)?.didExitFullScreen()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? DetachedJSONWindow, window === detachedWindow else { return }
        // Saved by hand rather than by autosave, so the tear-off gesture still
        // owns first placement; see DetachedJSONWindow.frameName.
        window.persistFrameUnlessFullScreen()
        detachedWindow = nil
        // Nothing is watching for ⌘+ / ⌘− any more until a surface reopens.
        if let keyMonitor, !popover.isShown {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        Diagnostics.info("detached window closed")
    }
}
