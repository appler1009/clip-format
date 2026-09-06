import Foundation

/// The result of trying to read some text as JSON: what both hosts render.
public struct PrettyJSONDocument: Sendable {
    /// Text as it arrived (clipboard string or file contents), trimmed.
    public let source: String
    public let indent: Int
    public let value: JSONValue?
    public let errorMessage: String?
    /// True when the formatted output was too long to show in full and the
    /// token stream stops early.
    public let isTruncated: Bool

    /// Syntax-classified formatted output, empty when the source is not JSON.
    /// Computed once at parse time — SwiftUI re-evaluates `body` far too often
    /// to re-run the printer per frame.
    public let tokens: [JSONToken]

    public var isValid: Bool { value != nil }

    public init(source: String, indent: Int, value: JSONValue?, errorMessage: String?, isTruncated: Bool = false) {
        self.source = source
        self.indent = indent
        self.value = value
        self.errorMessage = errorMessage

        guard let value else {
            self.tokens = []
            self.isTruncated = isTruncated
            return
        }
        let printed = PrettyPrinter.tokens(for: value, indent: indent)
        let length = printed.reduce(0) { $0 + $1.text.count }
        if length > JSONCanvas.renderCharacterLimit {
            self.tokens = JSONCanvas.truncate(printed, toCharacters: JSONCanvas.renderCharacterLimit)
            self.isTruncated = true
        } else {
            self.tokens = printed
            self.isTruncated = isTruncated
        }
    }

    public var prettyText: String? {
        value.map { PrettyPrinter.pretty($0, indent: indent) }
    }

    public var minifiedText: String? {
        value.map { PrettyPrinter.minified($0) }
    }

    /// A short one-line sample of the source, for the "not JSON" state.
    public func rawExcerpt(limit: Int = 400) -> String {
        let collapsed = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }
}
