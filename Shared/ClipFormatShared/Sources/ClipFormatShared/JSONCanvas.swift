import Foundation

/// The single entry point both hosts use. The menu-bar popover and the Quick
/// Look extension call these functions and nothing else, so a change to
/// formatting or colour lands in both at once.
public enum JSONCanvas {
    /// Formatted output beyond this many characters is cut off with a notice.
    /// That is already thousands of screens of JSON; rendering more only costs
    /// the popover and Quick Look their responsiveness.
    public static let renderCharacterLimit = 500_000

    /// Sources larger than this are refused outright rather than parsed.
    public static let sourceByteLimit = 32 * 1024 * 1024

    // MARK: - Model

    public static func model(from text: String, indent: Int = 2) -> PrettyJSONDocument {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return PrettyJSONDocument(source: trimmed, indent: indent, value: nil,
                                      errorMessage: "Clipboard is empty")
        }
        guard trimmed.utf8.count <= sourceByteLimit else {
            return PrettyJSONDocument(source: String(trimmed.prefix(4_000)), indent: indent, value: nil,
                                      errorTitle: "Too large",
                                      errorMessage: "Over the \(sourceByteLimit / 1_048_576) MB limit",
                                      isTruncated: true)
        }
        guard looksLikeJSON(trimmed) else {
            // The shape check reads the first and last character of the whole
            // buffer, which a JSON Lines file only satisfies when its first and
            // last records are the same kind of value: `{...}` then `[...]`
            // would fail it. Ask the line reader before giving up.
            switch lineDelimited(trimmed) {
            case .records(let records):
                return PrettyJSONDocument(source: trimmed, indent: indent,
                                          records: records, kind: .lineDelimited,
                                          errorMessage: nil)
            case .lineError(let error, let line):
                return PrettyJSONDocument(source: trimmed, indent: indent, value: nil,
                                          errorMessage: Self.message(for: error, onLine: line))
            case .notLineDelimited:
                return PrettyJSONDocument(source: trimmed, indent: indent, value: nil,
                                          errorMessage: "Not JSON")
            }
        }

        do {
            let value = try JSONParser.parse(trimmed)
            return PrettyJSONDocument(source: trimmed, indent: indent, value: value, errorMessage: nil)
        } catch let error as JSONParseError {
            // A JSON Lines file reads as a document that fails on trailing
            // content, so try it as lines before reporting that.
            switch lineDelimited(trimmed) {
            case .records(let records):
                return PrettyJSONDocument(source: trimmed, indent: indent,
                                          records: records, kind: .lineDelimited,
                                          errorMessage: nil)
            case .lineError(let lineError, let line):
                // Every line looked like JSON and one of them did not parse:
                // this was meant to be JSON Lines, so the offending line is
                // more use than the document's "trailing content" at line 2.
                return PrettyJSONDocument(source: trimmed, indent: indent, value: nil,
                                          errorMessage: Self.message(for: lineError, onLine: line))
            case .notLineDelimited:
                return PrettyJSONDocument(source: trimmed, indent: indent, value: nil,
                                          errorMessage: error.message)
            }
        } catch {
            return PrettyJSONDocument(source: trimmed, indent: indent, value: nil,
                                      errorMessage: error.localizedDescription)
        }
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
                             byteLimit: Int = sourceByteLimit) throws -> PrettyJSONDocument {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > byteLimit else {
            return model(from: try Data(contentsOf: url, options: .mappedIfSafe), indent: indent)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 4_000) ?? Data()
        let actual = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        let limit = ByteCountFormatter.string(fromByteCount: Int64(byteLimit), countStyle: .file)
        return PrettyJSONDocument(source: String(decoding: head, as: UTF8.self), indent: indent,
                                  value: nil,
                                  errorTitle: "Too large",
                                  errorMessage: "\(actual) file, over the \(limit) preview limit",
                                  isTruncated: true)
    }

    public static func model(from data: Data, indent: Int = 2) -> PrettyJSONDocument {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return PrettyJSONDocument(source: "", indent: indent, value: nil,
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

    static func truncate(_ tokens: [JSONToken], toCharacters limit: Int) -> [JSONToken] {
        var kept: [JSONToken] = []
        var count = 0
        for token in tokens {
            if count + token.text.count > limit { break }
            count += token.text.count
            kept.append(token)
        }
        kept.append(JSONToken(kind: .whitespace, text: "\n"))
        kept.append(JSONToken(kind: .punctuation, text: "… truncated"))
        return kept
    }

    // MARK: - HTML rendering

    /// Renders a full standalone HTML document.
    /// - Parameter appearance: pass `nil` to follow the host's colour scheme via
    ///   `prefers-color-scheme`, or force one for hosts that report it directly.
    public static func html(from document: PrettyJSONDocument,
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

    static func cssClass(for kind: JSONToken.Kind) -> String {
        switch kind {
        case .key: return "k"
        case .string: return "s"
        case .number: return "n"
        case .bool, .null: return "l"
        case .punctuation: return "p"
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
