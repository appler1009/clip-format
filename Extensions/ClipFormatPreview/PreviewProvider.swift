import ClipFormatShared
import CoreGraphics
import Foundation
import QuickLookUI
import UniformTypeIdentifiers

/// Quick Look preview for `.json` files.
///
/// The extension is sandboxed and cannot talk to the running menu-bar app.
/// Indent and font size come from the App Group defaults the app writes;
/// tokens and colours still come from `ClipFormatShared`.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    /// Files above this size are previewed from a leading slice only; Quick Look
    /// budgets a few seconds and a 200 MB log is not worth the wait.
    private static let byteLimit = 8 * 1024 * 1024

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let prefs = SharedFormattingPreferences.load()
        let document = try Self.document(for: request.fileURL, indent: prefs.indentWidth)
        let html = Data(JSONCanvas.html(from: document, appearance: nil,
                                        fontSize: CGFloat(prefs.fontSize)).utf8)

        return QLPreviewReply(dataOfContentType: .html,
                              contentSize: CGSize(width: 800, height: 600)) { reply in
            reply.stringEncoding = .utf8
            return html
        }
    }

    static func document(for url: URL, indent: Int = AppGroup.defaultIndentWidth) throws -> PrettyJSONDocument {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: byteLimit) ?? Data()
        return JSONCanvas.model(from: data, indent: indent)
    }
}
