import Foundation

/// The single entry point both hosts use. The menu-bar popover and the Quick
/// Look extension call these functions and nothing else, so a change to
/// formatting or colour lands in both at once.
public enum FormatCanvas {
    /// Formatted output beyond this many characters is cut off with a notice.
    /// That is already thousands of screens of JSON; rendering more only costs
    /// the popover and Quick Look their responsiveness.
    public static let renderCharacterLimit = 500_000

    /// Sources larger than this are refused outright rather than parsed.
    public static let sourceByteLimit = 32 * 1024 * 1024

    // MARK: - Model

    public static func model(from text: String, indent: Int = 2) -> FormattedDocument {
        // A byte order mark is not whitespace to `trimmingCharacters`, so it
        // would survive and sit in front of the first `{` or `<` — where every
        // shape check in this function looks. Editors on Windows write one
        // routinely, and the loop covers the rarer case of one that is not the
        // very first scalar.
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("\u{FEFF}") {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !trimmed.isEmpty else {
            return FormattedDocument(source: trimmed, indent: indent, value: nil,
                                      errorMessage: "Clipboard is empty")
        }
        guard trimmed.utf8.count <= sourceByteLimit else {
            return FormattedDocument(source: String(trimmed.prefix(4_000)), indent: indent, value: nil,
                                      errorTitle: "Too large",
                                      errorMessage: "Over the \(sourceByteLimit / 1_048_576) MB limit",
                                      isTruncated: true)
        }

        // An opening angle bracket means XML, and nothing that follows can be
        // JSON, so it is decided here rather than after the JSON readings have
        // failed. Deciding it later put the XML branch out of reach: almost
        // every XML document contains a namespace URL, and the `//` in it made
        // the JSONC stage claim the source and report "unexpected '<'".
        if trimmed.hasPrefix("<") {
            do {
                return FormattedDocument(source: trimmed, indent: indent,
                                         xmlNodes: try XMLReader.parse(trimmed))
            } catch let error as XMLParseError {
                return FormattedDocument(source: trimmed, indent: indent, xmlNodes: [],
                                         errorTitle: "Not XML", errorMessage: error.message)
            } catch {
                return FormattedDocument(source: trimmed, indent: indent, xmlNodes: [],
                                         errorTitle: "Not XML", errorMessage: error.localizedDescription)
            }
        }

        // One strict JSON document is the common case, and it is tried first so
        // that nothing else can loosen what "valid JSON" means.
        var documentError: JSONParseError?
        if looksLikeJSON(trimmed) {
            do {
                let value = try JSONParser.parse(trimmed)
                return FormattedDocument(source: trimmed, indent: indent, value: value, errorMessage: nil)
            } catch let error as JSONParseError {
                documentError = error
            } catch {
                return FormattedDocument(source: trimmed, indent: indent, value: nil,
                                          errorMessage: error.localizedDescription)
            }
        }

        // JSON Lines, which reads as a document that fails on trailing content.
        switch lineDelimited(trimmed) {
        case .records(let records):
            return FormattedDocument(source: trimmed, indent: indent,
                                      records: records, kind: .lineDelimited, errorMessage: nil)
        case .lineError(let lineError, let line):
            // Every line looked like JSON and one did not parse: this was meant
            // to be JSON Lines, so the offending line beats the document's
            // "trailing content" at line 2.
            return FormattedDocument(source: trimmed, indent: indent, value: nil,
                                      errorMessage: Self.message(for: lineError, onLine: line))
        case .notLineDelimited:
            break
        }

        // JSONC: comments and trailing commas. Anything succeeding here needed
        // those rules, since strict parsing has already been tried. Objects and
        // arrays only, the same rule `looksLikeJSON` applies to the other
        // kinds: `// note` followed by `42` is no more a JSONC document than a
        // bare `42` is a JSON one.
        //
        // Once the source is committed to this stage — strict already failed,
        // or a comment marker is present — the error from *this* parse is the
        // one to report. A commented file with something genuinely wrong in it
        // fails strict at the first `/`, and saying so would point at the
        // comment rather than at the fault.
        // Cheap and deliberately loose: a marker inside a string would also
        // match, but this only decides which error is shown, never whether the
        // source is valid.
        let isJSONCShaped = documentError != nil || trimmed.contains("//") || trimmed.contains("/*")
        do {
            let value = try JSONParser.parse(trimmed, options: .jsonc)
            if value.isContainer {
                return FormattedDocument(source: trimmed, indent: indent,
                                          records: [value], kind: .jsonc, errorMessage: nil)
            }
        } catch let commentError as JSONParseError where isJSONCShaped {
            return FormattedDocument(source: trimmed, indent: indent, value: nil,
                                      errorMessage: commentError.message)
        } catch {
            // Not JSON in any reading; fall through to the document's own error.
        }

        return FormattedDocument(source: trimmed, indent: indent, value: nil,
                                  errorMessage: documentError?.message ?? "Not JSON")
    }

    /// What reading the source as JSON Lines turned up.
    enum LineDelimitedResult {
        case records([JSONValue])
        /// Every line looked like JSON and one of them did not parse. Kept
        /// rather than discarded, because for a file that was clearly meant to
        /// be JSON Lines this error beats the whole-document one.
        case lineError(JSONParseError, line: Int)
        /// Not JSON Lines at all — say nothing and let the caller report the
        /// document's own failure.
        case notLineDelimited
    }

    /// Reads `trimmed` as JSON Lines (NDJSON): one JSON value per line.
    ///
    /// Objects and arrays only, matching `looksLikeJSON`: a file of bare
    /// numbers is not what anyone means by JSON Lines. A line that does not
    /// even look like JSON means this was never a JSON Lines file, so a
    /// pretty-printed document with a typo keeps its own parse error rather
    /// than being re-read as lines.
    static func lineDelimited(_ trimmed: String) -> LineDelimitedResult {
        var lines: [(text: String, number: Int)] = []
        for (offset, line) in trimmed.split(whereSeparator: \.isNewline).enumerated() {
            let text = line.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { lines.append((text, offset + 1)) }
        }
        guard lines.count > 1 else { return .notLineDelimited }

        // Cheap gate before parsing megabytes of something that is not JSON at
        // all: the first line has to look right.
        guard looksLikeJSON(lines[0].text) else { return .notLineDelimited }

        var records: [JSONValue] = []
        records.reserveCapacity(lines.count)
        for line in lines {
            guard looksLikeJSON(line.text) else { return .notLineDelimited }
            do {
                // Strict, deliberately: JSON Lines is defined as one *valid
                // JSON* value per line, and a record with a trailing comma is
                // a malformed record rather than a loosely written document.
                // Reading lines with `.jsonc` would also blunt the error, which
                // here can name the line that is wrong.
                records.append(try JSONParser.parse(line.text))
            } catch let error as JSONParseError {
                return .lineError(error, line: line.number)
            } catch {
                return .notLineDelimited
            }
        }
        return .records(records)
    }

    /// The parser reports a position within the one line it was given, so the
    /// line number is restated as the one in the file.
    private static func message(for error: JSONParseError, onLine line: Int) -> String {
        "\(error.reason) (line \(line), column \(error.column))"
    }

    /// Reads a file as JSON.
    ///
    /// The whole file is read or none of it is. Parsing needs a complete
    /// document, so handing the parser a leading slice of a large file reports
    /// good JSON as malformed; past `byteLimit` we say so by size instead.
    ///
    /// - Parameter byteLimit: overridable for tests; production callers take
    ///   the default.
    public static func model(contentsOf url: URL, indent: Int = 2,
                             byteLimit: Int = sourceByteLimit) throws -> FormattedDocument {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > byteLimit else {
            return model(from: try Data(contentsOf: url, options: .mappedIfSafe), indent: indent)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 4_000) ?? Data()
        let actual = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        let limit = ByteCountFormatter.string(fromByteCount: Int64(byteLimit), countStyle: .file)
        return FormattedDocument(source: String(decoding: head, as: UTF8.self), indent: indent,
                                  value: nil,
                                  errorTitle: "Too large",
                                  errorMessage: "\(actual) file, over the \(limit) preview limit",
                                  isTruncated: true)
    }

    public static func model(from data: Data, indent: Int = 2) -> FormattedDocument {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return FormattedDocument(source: "", indent: indent, value: nil,
                                      errorMessage: "File is not readable text")
        }
        return model(from: text, indent: indent)
    }

    /// Cheap pre-check so we do not run the parser over every clipboard change.
    /// A bare `"string"`, number, or `true` is technically valid JSON, but
    /// flagging every copied word as JSON would make the menu-bar badge useless.
    public static func looksLikeJSON(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, let last = trimmed.last else { return false }
        return (first == "{" && last == "}") || (first == "[" && last == "]")
    }

    static func truncate(_ tokens: [SyntaxToken], toCharacters limit: Int) -> [SyntaxToken] {
        var kept: [SyntaxToken] = []
        var count = 0
        for token in tokens {
            if count + token.text.count > limit { break }
            count += token.text.count
            kept.append(token)
        }
        kept.append(SyntaxToken(kind: .whitespace, text: "\n"))
        kept.append(SyntaxToken(kind: .punctuation, text: "… truncated"))
        return kept
    }

    // MARK: - HTML rendering

    /// Renders a full standalone HTML document.
    /// - Parameter appearance: pass `nil` to follow the host's colour scheme via
    ///   `prefers-color-scheme`, or force one for hosts that report it directly.
    public static func html(from document: FormattedDocument,
                            appearance: Appearance? = nil,
                            fontSize: CGFloat = 12) -> String {
        let body: String
        if document.isValid {
            var code = ""
            code.reserveCapacity(document.tokens.count * 12)
            var index = document.tokens.startIndex
            while index < document.tokens.endIndex {
                let kind = document.tokens[index].kind
                // Coalesce neighbouring tokens of the same kind into one span.
                var run = ""
                while index < document.tokens.endIndex, document.tokens[index].kind == kind {
                    run += escapeHTML(document.tokens[index].text)
                    index += 1
                }
                if kind == .whitespace {
                    code += run
                } else {
                    code += "<span class=\"\(cssClass(for: kind))\">\(run)</span>"
                }
            }
            body = "<pre class=\"json\">\(code)</pre>"
        } else {
            let title = escapeHTML(document.errorTitle)
            let message = escapeHTML(document.errorMessage ?? "Not JSON")
            let excerpt = escapeHTML(document.rawExcerpt(limit: 2_000))
            body = """
            <div class="notice"><span class="badge">\(title)</span><span class="reason">\(message)</span></div>
            <pre class="raw">\(excerpt)</pre>
            """
        }

        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>\(css(appearance: appearance, fontSize: fontSize, tabSize: document.indent))</style>
        </head><body>\(body)</body></html>
        """
    }

    private static func css(appearance: Appearance?, fontSize: CGFloat, tabSize: Int) -> String {
        let px = String(format: "%.1f", fontSize)
        let tabs = max(2, tabSize)
        let base = """
        :root { color-scheme: light dark; }
        * { box-sizing: border-box; }
        body {
          margin: 0;
          padding: 14px 18px;
          font: \(px)px/1.55 ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace;
          background: var(--bg);
          color: var(--fg);
          -webkit-font-smoothing: antialiased;
        }
        pre.json, pre.raw { margin: 0; white-space: pre; tab-size: \(tabs); }
        pre.raw {
          white-space: pre-wrap;
          word-break: break-word;
          color: var(--fg2);
          background: var(--bg2);
          padding: 10px 12px;
          border-radius: 8px;
        }
        .k { color: var(--key); }
        .s { color: var(--string); }
        .n { color: var(--number); }
        .l { color: var(--literal); }
        .p { color: var(--punctuation); }
        .c { color: var(--fg2); font-style: italic; }
        .t { color: var(--fg); }
        .notice {
          display: flex; align-items: center; gap: 8px;
          font: 12px/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
          margin-bottom: 10px;
        }
        .badge {
          background: var(--error); color: #fff;
          padding: 2px 8px; border-radius: 999px; font-weight: 600; font-size: 11px;
        }
        .reason { color: var(--fg2); }
        """

        func variables(_ theme: Theme) -> String {
            """
            --bg: \(theme.background.hexString);
            --bg2: \(theme.secondaryBackground.hexString);
            --fg: \(theme.foreground.hexString);
            --fg2: \(theme.secondaryForeground.hexString);
            --key: \(theme.key.hexString);
            --string: \(theme.string.hexString);
            --number: \(theme.number.hexString);
            --literal: \(theme.literal.hexString);
            --punctuation: \(theme.punctuation.hexString);
            --error: \(theme.error.hexString);
            """
        }

        if let appearance {
            return ":root {\(variables(Theme.theme(for: appearance)))}\n" + base
        }
        return """
        :root {\(variables(.light))}
        @media (prefers-color-scheme: dark) { :root {\(variables(.dark))} }
        """ + "\n" + base
    }

    static func cssClass(for kind: SyntaxToken.Kind) -> String {
        switch kind {
        case .key, .tagName: return "k"
        case .string: return "s"
        case .number: return "n"
        case .bool, .null, .attributeName: return "l"
        case .punctuation: return "p"
        case .comment: return "c"
        case .text: return "t"
        case .whitespace: return ""
        }
    }

    static func escapeHTML(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(character)
            }
        }
        return out
    }
}
