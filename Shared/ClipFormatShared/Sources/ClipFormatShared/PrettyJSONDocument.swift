import Foundation

/// What the source turned out to be.
public enum DocumentKind: String, Sendable, Equatable {
    /// One JSON document.
    case json
    /// JSON Lines (also called NDJSON): one JSON value per line.
    case lineDelimited
    /// JSON with comments, as in JSONC and `tsconfig.json`.
    case commented
}

/// The result of trying to read some text as JSON: what both hosts render.
public struct PrettyJSONDocument: Sendable {
    /// Text as it arrived (clipboard string or file contents), trimmed.
    public let source: String
    public let indent: Int
    public let kind: DocumentKind
    /// Every record parsed from the source: one for a JSON document, one per
    /// line for JSON Lines. Empty when the source did not parse.
    public let records: [JSONValue]
    /// Short label for the failure state, shown as the badge in both hosts.
    /// "Not JSON" is right for most failures but wrong for a file we refused
    /// to read on size alone, which may well be perfectly good JSON.
    public let errorTitle: String
    public let errorMessage: String?
    /// True when the formatted output was too long to show in full and the
    /// token stream stops early.
    public let isTruncated: Bool

    /// Syntax-classified formatted output, empty when the source is not JSON.
    /// Computed once at parse time — SwiftUI re-evaluates `body` far too often
    /// to re-run the printer per frame.
    public let tokens: [JSONToken]

    public var isValid: Bool { !records.isEmpty }

    /// The single value, when the source held one JSON document. Nil for JSON
    /// Lines, which has no one value — use `records`.
    public var value: JSONValue? { kind == .json ? records.first : nil }

    /// How many lines parsed, for the "17 records" the hosts show.
    public var recordCount: Int { records.count }

    public init(source: String, indent: Int, value: JSONValue?,
                errorTitle: String = "Not JSON", errorMessage: String?,
                isTruncated: Bool = false) {
        self.init(source: source, indent: indent,
                  records: value.map { [$0] } ?? [], kind: .json,
                  errorTitle: errorTitle, errorMessage: errorMessage,
                  isTruncated: isTruncated)
    }

    public init(source: String, indent: Int, records: [JSONValue], kind: DocumentKind,
                errorTitle: String = "Not JSON", errorMessage: String?,
                isTruncated: Bool = false) {
        self.source = source
        self.indent = indent
        self.records = records
        self.kind = kind
        self.errorTitle = errorTitle
        self.errorMessage = errorMessage

        guard !records.isEmpty else {
            self.tokens = []
            self.isTruncated = isTruncated
            return
        }
        let printed = Self.tokens(for: records, kind: kind, indent: indent)
        let length = printed.reduce(0) { $0 + $1.text.count }
        if length > JSONCanvas.renderCharacterLimit {
            self.tokens = JSONCanvas.truncate(printed, toCharacters: JSONCanvas.renderCharacterLimit)
            self.isTruncated = true
        } else {
            self.tokens = printed
            self.isTruncated = isTruncated
        }
    }

    /// A blank line between records keeps a JSON Lines file readable once each
    /// record is expanded over several lines of its own.
    private static func tokens(for records: [JSONValue], kind: DocumentKind, indent: Int) -> [JSONToken] {
        guard kind == .lineDelimited else {
            return PrettyPrinter.tokens(for: records[0], indent: indent)
        }
        var tokens: [JSONToken] = []
        for (offset, record) in records.enumerated() {
            if offset > 0 { tokens.append(JSONToken(kind: .whitespace, text: "\n\n")) }
            tokens.append(contentsOf: PrettyPrinter.tokens(for: record, indent: indent))
        }
        return tokens
    }

    public var prettyText: String? {
        guard !records.isEmpty else { return nil }
        guard kind == .lineDelimited else { return PrettyPrinter.pretty(records[0], indent: indent) }
        return records.map { PrettyPrinter.pretty($0, indent: indent) }.joined(separator: "\n\n")
    }

    /// For JSON Lines this is the file's own shape — one minified record per
    /// line — so Copy Minified round-trips rather than producing an array.
    public var minifiedText: String? {
        guard !records.isEmpty else { return nil }
        return records.map { PrettyPrinter.minified($0) }.joined(separator: "\n")
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
