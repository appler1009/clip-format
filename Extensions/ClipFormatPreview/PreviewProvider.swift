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
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let prefs = SharedFormattingPreferences.load()
        let document = try Self.document(for: request.fileURL, indent: prefs.indentWidth)
        let html = Data(FormatCanvas.html(from: document, appearance: nil,
                                        fontSize: CGFloat(prefs.fontSize)).utf8)

        return QLPreviewReply(dataOfContentType: .html,
                              contentSize: CGSize(width: 800, height: 600)) { reply in
            reply.stringEncoding = .utf8
            return html
        }
    }

    static func document(for url: URL, indent: Int = AppGroup.defaultIndentWidth) throws -> FormattedDocument {
        try FormatCanvas.model(contentsOf: url, indent: indent)
    }
}
