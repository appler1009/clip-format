import ClipFormatShared
import CoreGraphics
import Foundation
import QuickLookUI
import UniformTypeIdentifiers

/// Quick Look preview for `.json` files.
///
/// The extension is sandboxed and sees only the requested file — it never talks
/// to the menu-bar app. Everything it renders comes from `ClipFormatShared`, so
/// Spacebar in Finder and the popover show byte-identical formatting.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    /// Files above this size are previewed from a leading slice only; Quick Look
    /// budgets a few seconds and a 200 MB log is not worth the wait.
    private static let byteLimit = 8 * 1024 * 1024

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let document = try Self.document(for: request.fileURL)
        let html = Data(JSONCanvas.html(from: document, appearance: nil).utf8)

        return QLPreviewReply(dataOfContentType: .html,
                              contentSize: CGSize(width: 800, height: 600)) { reply in
            reply.stringEncoding = .utf8
            return html
        }
    }

    static func document(for url: URL) throws -> PrettyJSONDocument {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: byteLimit) ?? Data()
        return JSONCanvas.model(from: data, indent: 2)
    }
}
