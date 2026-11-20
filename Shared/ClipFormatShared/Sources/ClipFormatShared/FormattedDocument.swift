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
    /// YAML, highlighted and re-indented line by line rather than parsed.
    case yaml
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

    public var isValid: Bool { !records.isEmpty || !xmlNodes.isEmpty || isValidYAML }

    /// YAML has no tree to check for emptiness, so its success is recorded.
    private let isValidYAML: Bool

    /// The single value, when the source held one document — with or without
    /// comments. Nil only for JSON Lines, which genuinely has no one value;
    /// use `records` there.
    public var value: JSONValue? { kind == .lineDelimited ? nil : records.first }

    /// How many lines parsed, for the "17 records" the hosts show.
    public var recordCount: Int { records.count }

    /// Every public initialiser lands here, so each field is set in one place.
    private init(source: String, indent: Int, kind: DocumentKind,
                 records: [JSONValue] = [], xmlNodes: [XMLValue] = [], isValidYAML: Bool = false,
                 printed: (tokens: [SyntaxToken], isTruncated: Bool),
                 errorTitle: String, errorMessage: String?, isTruncated: Bool) {
        self.source = source
        self.indent = indent
        self.kind = kind
        self.records = records
        self.xmlNodes = xmlNodes
        self.isValidYAML = isValidYAML
        self.tokens = printed.tokens
        self.isTruncated = isTruncated || printed.isTruncated
        self.errorTitle = errorTitle
        self.errorMessage = errorMessage
    }

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
        let printed = xmlNodes.isEmpty
            ? ([], false)
            : XMLPrinter.tokens(for: xmlNodes, indent: indent,
                                characterLimit: FormatCanvas.renderCharacterLimit)
        self.init(source: source, indent: indent, kind: .xml, xmlNodes: xmlNodes,
                  printed: printed, errorTitle: errorTitle, errorMessage: errorMessage,
                  isTruncated: isTruncated)
    }

    /// YAML. Pass no `yaml` and an error for the failure case; the document
    /// still reports `.yaml`, as XML does.
    public init(source: String, indent: Int,
                yaml: (tokens: [SyntaxToken], isTruncated: Bool)?,
                errorTitle: String = "Not YAML", errorMessage: String? = nil) {
        self.init(source: source, indent: indent, kind: .yaml,
                  isValidYAML: !(yaml?.tokens.isEmpty ?? true),
                  printed: yaml ?? ([], false),
                  errorTitle: errorTitle, errorMessage: errorMessage, isTruncated: false)
    }

    public init(source: String, indent: Int, records: [JSONValue], kind: DocumentKind,
                errorTitle: String = "Not JSON", errorMessage: String?,
                isTruncated: Bool = false) {
        let printed = records.isEmpty
            ? ([], false)
            : Self.tokens(for: records, kind: kind, indent: indent,
                          characterLimit: FormatCanvas.renderCharacterLimit)
        self.init(source: source, indent: indent, kind: kind, records: records,
                  printed: printed, errorTitle: errorTitle, errorMessage: errorMessage,
                  isTruncated: isTruncated)
    }

    /// A blank line between records keeps a JSON Lines file readable once each
    /// record is expanded over several lines of its own.
    private static func tokens(for records: [JSONValue], kind: DocumentKind, indent: Int,
                               characterLimit: Int) -> (tokens: [SyntaxToken], isTruncated: Bool) {
        guard kind == .lineDelimited else {
            return PrettyPrinter.tokens(for: records[0], indent: indent, characterLimit: characterLimit)
        }
        var sink = TokenSink(limit: characterLimit, reserve: records.count * 8)
        for (offset, record) in records.enumerated() {
            if offset > 0 { sink.append(.whitespace, "\n\n") }
            PrettyPrinter.emit(record, indent: indent, level: 0, into: &sink)
            if sink.isTruncated { break }
        }
        return sink.finish()
    }

    /// Formatted text for Copy Pretty. Uses the display token stream when it
    /// holds the whole document; regenerates from the AST when the preview was
    /// truncated so Copy still yields everything.
    public var prettyText: String? {
        guard isValid else { return nil }
        if !isTruncated { return tokens.map(\.text).joined() }
        switch kind {
        case .yaml:
            return YAMLFormatter.pretty(source, indent: indent)
        case .xml:
            return XMLPrinter.pretty(xmlNodes, indent: indent)
        case .lineDelimited:
            return records.map { PrettyPrinter.pretty($0, indent: indent) }.joined(separator: "\n\n")
        case .json, .jsonc:
            return PrettyPrinter.pretty(records[0], indent: indent)
        }
    }

    /// For JSON Lines this is the file's own shape — one minified record per
    /// line — so Copy Minified round-trips rather than producing an array.
    public var minifiedText: String? {
        guard isValid else { return nil }
        switch kind {
        case .yaml:
            // YAML's indentation is its structure; there is no smaller form.
            return nil
        case .xml:
            return XMLPrinter.minified(xmlNodes)
        case .json, .jsonc, .lineDelimited:
            return records.map { PrettyPrinter.minified($0) }.joined(separator: "\n")
        }
    }

    /// A short sample of the source, for the state shown when it did not format.
    public func rawExcerpt(limit: Int = 400) -> String {
        let collapsed = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }
}
