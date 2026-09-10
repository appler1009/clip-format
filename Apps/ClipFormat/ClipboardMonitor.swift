import AppKit
import ClipFormatShared
import Combine

/// Watches the general pasteboard and republishes it as a `FormattedDocument`.
///
/// AppKit has no pasteboard-change notification, so we poll `changeCount` — the
/// cheap integer read, not the payload — and only re-read the contents when it
/// moves.
@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published private(set) var document: FormattedDocument
    @Published private(set) var isFormatting = false

    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?
    private var indentObservation: AnyCancellable?
    private let preferences: Preferences
    private var generation = 0

    /// Payloads above this size are parsed off the main thread. Kept low so a
    /// mid-size pretty-print cannot hitch the status-item click path.
    private static let asyncThreshold = 64 * 1024

    init(pasteboard: NSPasteboard = .general, preferences: Preferences = .shared) {
        self.pasteboard = pasteboard
        self.preferences = preferences
        self.lastChangeCount = pasteboard.changeCount - 1
        self.document = FormatCanvas.model(from: "", indent: preferences.indentWidth)

        // The new indent has to come from the stream: `@Published` fires in
        // `willSet`, so reading `preferences.indentWidth` here would re-render
        // with the value the user just replaced.
        indentObservation = preferences.$indentWidth
            .dropFirst()
            .sink { [weak self] indent in self?.refresh(force: true, indent: indent) }
    }

    func start(interval: TimeInterval = 0.75) {
        stop()
        refresh(force: true)
        // Target/selector keeps the tick on the main run-loop without allocating
        // a `Task` every 0.75s when the pasteboard has not moved.
        let timer = Timer(timeInterval: interval, target: self,
                          selector: #selector(timerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func timerFired() {
        refresh()
    }

    func refresh(force: Bool = false, indent: Int? = nil) {
        let indent = indent ?? preferences.indentWidth
        let changeCount = pasteboard.changeCount
        guard force || changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        generation &+= 1
        let generation = self.generation

        let snapshot = snapshotPasteboard()
        switch snapshot {
        case .empty:
            document = FormatCanvas.model(from: "", indent: indent)
            isFormatting = false

        case .text(let text) where text.utf8.count <= Self.asyncThreshold:
            document = FormatCanvas.model(from: text, indent: indent)
            isFormatting = false

        case .text(let text):
            isFormatting = true
            Task.detached(priority: .userInitiated) {
                let model = FormatCanvas.model(from: text, indent: indent)
                await MainActor.run {
                    guard self.generation == generation else { return }
                    self.document = model
                    self.isFormatting = false
                }
            }

        case .file(let url):
            // Pasteboard yields the URL on the main thread; the file bytes and
            // parse move off it so a large Finder copy does not hitch the UI.
            isFormatting = true
            Task.detached(priority: .userInitiated) {
                let model: FormattedDocument
                if let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
                    model = FormatCanvas.model(from: data, indent: indent)
                } else {
                    model = FormatCanvas.model(from: "", indent: indent)
                }
                await MainActor.run {
                    guard self.generation == generation else { return }
                    self.document = model
                    self.isFormatting = false
                }
            }
        }
    }

    private enum Snapshot {
        case empty
        case text(String)
        case file(URL)
    }

    /// Prefers a copied `.json` file URL (bytes read off-main), then plain
    /// text, then the plain-text flattening of RTF. Pasteboard reads stay on
    /// the main actor — AppKit's contract.
    private func snapshotPasteboard() -> Snapshot {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first,
           ["json", "jsonc", "geojson", "webmanifest"].contains(url.pathExtension.lowercased()) {
            return .file(url)
        }
        if let text = pasteboard.string(forType: .string) {
            return .text(text)
        }
        if let rtf = pasteboard.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            return .text(attributed.string)
        }
        return .empty
    }
}
