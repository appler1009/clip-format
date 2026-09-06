import AppKit
import ClipFormatShared
import Combine

/// Watches the general pasteboard and republishes it as a `PrettyJSONDocument`.
///
/// AppKit has no pasteboard-change notification, so we poll `changeCount` — the
/// cheap integer read, not the payload — and only re-read the contents when it
/// moves.
@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published private(set) var document: PrettyJSONDocument
    @Published private(set) var isFormatting = false

    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?
    private var indentObservation: AnyCancellable?
    private let preferences: Preferences

    /// Payloads above this size are parsed off the main thread.
    private static let asyncThreshold = 256 * 1024

    init(pasteboard: NSPasteboard = .general, preferences: Preferences = .shared) {
        self.pasteboard = pasteboard
        self.preferences = preferences
        self.lastChangeCount = pasteboard.changeCount - 1
        self.document = JSONCanvas.model(from: "", indent: preferences.indentWidth)

        indentObservation = preferences.$indentWidth
            .dropFirst()
            .sink { [weak self] _ in self?.refresh(force: true) }
    }

    func start(interval: TimeInterval = 0.75) {
        stop()
        refresh(force: true)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // .common so polling survives menu tracking and window drags.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh(force: Bool = false) {
        let changeCount = pasteboard.changeCount
        guard force || changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        guard let text = readText() else {
            document = JSONCanvas.model(from: "", indent: preferences.indentWidth)
            return
        }

        let indent = preferences.indentWidth
        guard text.utf8.count > Self.asyncThreshold else {
            document = JSONCanvas.model(from: text, indent: indent)
            return
        }

        isFormatting = true
        Task.detached(priority: .userInitiated) {
            let model = JSONCanvas.model(from: text, indent: indent)
            await MainActor.run {
                // A newer copy may have landed while we were parsing.
                guard self.lastChangeCount == changeCount else { return }
                self.document = model
                self.isFormatting = false
            }
        }
    }

    /// Prefers a copied `.json` file's contents over its path string, then plain
    /// text, then the plain-text flattening of RTF.
    private func readText() -> String? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first,
           ["json", "jsonc", "geojson", "webmanifest"].contains(url.pathExtension.lowercased()),
           let data = try? Data(contentsOf: url, options: .mappedIfSafe),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = pasteboard.string(forType: .string) {
            return text
        }
        if let rtf = pasteboard.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            return attributed.string
        }
        return nil
    }
}
