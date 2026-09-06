import AppKit
import Combine
import SwiftUI

@main
struct ClipFormatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The UI lives in a status item, its popover, and a settings window the
        // delegate owns. This scene exists only to satisfy the SwiftUI
        // lifecycle; LSUIElement keeps the app out of the Dock.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let monitor = ClipboardMonitor()
    private let preferences = Preferences.shared
    private var cancellables: Set<AnyCancellable> = []
    private var eventMonitor: Any?
    private let preferencesWindow = PreferencesWindowController()

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
        monitor.refresh(force: true)
        // The user may have removed us from Login Items while we were inactive.
        preferences.refreshLaunchAtLoginStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        removeDismissMonitor()
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
        menu.addItem(withTitle: "Show Clipboard JSON", action: #selector(togglePopover), keyEquivalent: "")
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

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        let hosting = NSHostingController(
            rootView: PopoverView(
                monitor: monitor,
                preferences: preferences,
                openPreferences: { [weak self] in self?.openPreferences() },
                quit: { [weak self] in self?.quit() }
            )
        )
        // Without an explicit sizing policy the hosting controller reports a
        // zero preferred size and the popover opens invisibly.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 520, height: 420)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        monitor.refresh(force: true)
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
    }

    private func removeDismissMonitor() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    // MARK: - Menu actions

    @objc private func openPreferences() {
        popover.performClose(nil)
        preferencesWindow.show(preferences: preferences)
    }

    @objc private func showAbout() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "ClipFormat",
            .init(rawValue: "Copyright"): "Revived. Formats JSON in the menu bar and in Quick Look.",
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
