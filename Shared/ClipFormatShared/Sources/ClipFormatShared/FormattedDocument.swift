import Foundation

/// What the source turned out to be.
public enum DocumentKind: String, Sendable, Equatable {
    /// One JSON document.
    case json
    /// JSON Lines (also called NDJSON): one JSON value per line.
    case lineDelimited
    /// JSONC: JSON with comments and trailing commas, as `tsconfig.json` and
    /// VS Code settings are written.
    case jsonc
    /// XML.
    case xml
}

/// The result of trying to read some text as one of the formats this app
/// knows: what both hosts render.
public struct FormattedDocument: Sendable {
    /// Text as it arrived (clipboard string or file contents), trimmed.
    public let source: String
    public let indent: Int
    public let kind: DocumentKind
    /// Every record parsed from the source: one for a JSON document, one per
    /// line for JSON Lines. Empty for XML, and when the source did not parse.
    public let records: [JSONValue]
    /// The top-level XML nodes — the root element, and any comment or
    /// processing instruction beside it. Empty for every JSON kind.
    public let xmlNodes: [XMLValue]
    /// Short label for the failure state, shown as the badge in both hosts.
    /// "Not JSON" / "Not XML" name a format that was attempted; "Can't format"
    /// is for text that never looked like either. "Too large" is for a file we
    /// refused to read on size alone, which may well be perfectly good.
    public let errorTitle: String
    public let errorMessage: String?
    /// True when the formatted output was too long to show in full and the
    /// token stream stops early.
    public let isTruncated: Bool

    /// Syntax-classified formatted output, empty when the source did not parse
    /// as anything.
    /// Computed once at parse time — SwiftUI re-evaluates `body` far too often
    /// to re-run the printer per frame. Capped at `FormatCanvas.renderCharacterLimit`.
    public let tokens: [SyntaxToken]

    public var isValid: Bool { !records.isEmpty || !xmlNodes.isEmpty }

    /// The single value, when the source held one document — with or without
    /// comments. Nil only for JSON Lines, which genuinely has no one value;
    /// use `records` there.
    public var value: JSONValue? { kind == .lineDelimited ? nil : records.first }

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

    /// XML, whose tree is nothing like a JSON value's. Also the failure case:
    /// pass no nodes and an error, and the document still reports `.xml`, so
    /// callers can tell which format was being read without matching on the
    /// wording of the message.
    public init(source: String, indent: Int, xmlNodes: [XMLValue],
                errorTitle: String = "Not XML", errorMessage: String? = nil,
                isTruncated: Bool = false) {
        self.source = source
        self.indent = indent
        self.records = []
        self.xmlNodes = xmlNodes
        self.kind = .xml
        self.errorTitle = errorTitle
        self.errorMessage = errorMessage

        guard !xmlNodes.isEmpty else {
            self.tokens = []
            self.isTruncated = isTruncated
            return
        }
        let printed = XMLPrinter.tokens(for: xmlNodes, indent: indent,
                                        characterLimit: FormatCanvas.renderCharacterLimit)
        self.tokens = printed.tokens
        self.isTruncated = isTruncated || printed.isTruncated
    }

    public init(source: String, indent: Int, records: [JSONValue], kind: DocumentKind,
                errorTitle: String = "Not JSON", errorMessage: String?,
                isTruncated: Bool = false) {
        self.source = source
        self.indent = indent
        self.records = records
        self.xmlNodes = []
        self.kind = kind
        self.errorTitle = errorTitle
        self.errorMessage = errorMessage

        guard !records.isEmpty else {
            self.tokens = []
            self.isTruncated = isTruncated
            return
        }
        let printed = Self.tokens(for: records, kind: kind, indent: indent,
                                  characterLimit: FormatCanvas.renderCharacterLimit)
        self.tokens = printed.tokens
        self.isTruncated = isTruncated || printed.isTruncated
    }

    /// A blank line between records keeps a JSON Lines file readable once each
    /// record is expanded over several lines of its own.
    private static func tokens(for records: [JSONValue], kind: DocumentKind, indent: Int,
                               characterLimit: Int) -> (tokens: [SyntaxToken], isTruncated: Bool) {
        guard kind == .lineDelimited else {
            return PrettyPrinter.tokens(for: records[0], indent: indent, characterLimit: characterLimit)
        }
        var tokens: [SyntaxToken] = []
        tokens.reserveCapacity(records.count * 8)
        var count = 0
        for (offset, record) in records.enumerated() {
            if offset > 0 {
                let gap = "\n\n"
                if count + gap.count > characterLimit {
                    tokens.append(SyntaxToken(kind: .whitespace, text: "\n"))
                    tokens.append(SyntaxToken(kind: .punctuation, text: "… truncated"))
                    return (tokens, true)
                }
                count += gap.count
                tokens.append(SyntaxToken(kind: .whitespace, text: gap))
            }
            let remaining = max(0, characterLimit - count)
            let printed = PrettyPrinter.tokens(for: record, indent: indent, characterLimit: remaining)
            tokens.append(contentsOf: printed.tokens)
            if printed.isTruncated { return (tokens, true) }
            count += printed.tokens.reduce(0) { $0 + $1.text.count }
        }
        return (tokens, false)
    }

    /// Formatted text for Copy Pretty. Uses the display token stream when it
    /// holds the whole document; regenerates from the AST when the preview was
    /// truncated so Copy still yields everything.
    public var prettyText: String? {
        if kind == .xml {
            guard !xmlNodes.isEmpty else { return nil }
            if !isTruncated { return tokens.map(\.text).joined() }
            return XMLPrinter.pretty(xmlNodes, indent: indent)
        }
        guard !records.isEmpty else { return nil }
        if !isTruncated { return tokens.map(\.text).joined() }
        guard kind == .lineDelimited else { return PrettyPrinter.pretty(records[0], indent: indent) }
        return records.map { PrettyPrinter.pretty($0, indent: indent) }.joined(separator: "\n\n")
    }

    /// For JSON Lines this is the file's own shape — one minified record per
    /// line — so Copy Minified round-trips rather than producing an array.
    public var minifiedText: String? {
        if kind == .xml {
            return xmlNodes.isEmpty ? nil : XMLPrinter.minified(xmlNodes)
        }
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
