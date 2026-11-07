import Sparkle

/// ClipFormat updating itself: Sparkle looks daily at the feed the app was
/// built with, and asks before it installs.
@MainActor
final class AppUpdates: ObservableObject {
    static let shared = AppUpdates()

    /// Nil when the build has no feed or key (one of your own): nothing looks.
    private let controller: SPUStandardUpdaterController?

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String) ?? ""
        let key = (info["SUPublicEDKey"] as? String) ?? ""
        controller = feed.isEmpty || key.isEmpty
            ? nil
            : SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var available: Bool { controller != nil }

    func check() { controller?.checkForUpdates(nil) }

    /// Looking by itself, daily; kept by Sparkle.
    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }
}
