import Foundation

/// Why a source could not be formatted as YAML, with the line it was found on.
public struct YAMLFormatError: Error, Equatable, Sendable {
    public let reason: String
    public let line: Int

    public var message: String { "\(reason) (line \(line))" }
}

/// Highlights and re-indents YAML without building a tree.
///
/// A tree round trip loses comments, anchors and the way block scalars are
/// written, which is most of what people care about in a YAML file. This works
/// line by line instead: it recolours what is there, moves each line to a
/// consistent indentation, and leaves the text itself alone.
///
/// Validation is shallow on purpose — tab indentation, a dedent that matches no
/// enclosing level, and an unterminated quote or bracket. It does not claim to
/// accept or reject everything a real YAML parser would.
public enum YAMLFormatter {
    // MARK: - Public

    public static func tokens(for source: String, indent: Int,
                              characterLimit: Int = .max) throws -> (tokens: [SyntaxToken], isTruncated: Bool) {
        var run = Run(width: max(1, indent), limit: characterLimit)
        let text = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var number = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            number += 1
            try run.consume(line, number: number)
            if run.sink.isTruncated { break }
        }
        if !run.sink.isTruncated { try run.finish() }
        return run.sink.finish()
    }

    public static func pretty(_ source: String, indent: Int) -> String? {
        guard let result = try? tokens(for: source, indent: indent) else { return nil }
        return result.tokens.map(\.text).joined()
    }

    /// Strict shape check for text that arrives with no file name to go on.
    /// Almost any prose is valid YAML, so the clipboard has to show clear
    /// structure: a leading `---`, or at least one `key: value` line among two
    /// or more structured lines, and nothing at the top level that is neither.
    public static func looksLikeYAML(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, !"{[<".contains(first) else { return false }
        var structured = 0
        var keyLines = 0
        var sawContent = false
        var startedWithMarker = false

        for raw in trimmed.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.hasSuffix("\r") ? raw.dropLast() : raw
            let indentWidth = line.prefix(while: { $0 == " " }).count
            let rest = line.dropFirst(indentWidth)
            if rest.isEmpty || rest.allSatisfy(\.isWhitespace) { continue }
            if rest.first == "\t" { return false }
            if rest.first == "#" { continue }
            if indentWidth == 0, rest == "---" || rest.hasPrefix("--- ") || rest == "..." {
                if !sawContent { startedWithMarker = true }
                sawContent = true
                continue
            }
            sawContent = true

            var body = rest
            var isStructured = false
            while body == "-" || body.hasPrefix("- ") {
                isStructured = true
                body = body.dropFirst().drop(while: { $0 == " " })
            }
            if let key = splitKey(body), isSimpleKey(key.key) {
                isStructured = true
                keyLines += 1
            }
            if isStructured {
                structured += 1
            } else if indentWidth == 0 {
                return false
            }
        }
        if startedWithMarker { return structured >= 1 }
        return keyLines >= 1 && structured >= 2
    }

    // MARK: - Keys

    struct KeySplit {
        let key: Substring
        /// Index just past the colon.
        let afterColon: Substring.Index
    }

    /// Finds `key:` at the start of `text`. The colon has to be followed by a
    /// space or the end of the line, which is what keeps `http://host` and
    /// `12:30` from being read as keys.
    static func splitKey(_ text: Substring) -> KeySplit? {
        guard let first = text.first else { return nil }
        if first == "\"" || first == "'" {
            var index = text.index(after: text.startIndex)
            while index < text.endIndex {
                let ch = text[index]
                if first == "\"", ch == "\\" {
                    index = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                    continue
                }
                if ch == first {
                    let next = text.index(after: index)
                    if first == "'", next < text.endIndex, text[next] == "'" {
                        index = text.index(after: next)
                        continue
                    }
                    guard next < text.endIndex, text[next] == ":" else { return nil }
                    let after = text.index(after: next)
                    guard after == text.endIndex || text[after] == " " || text[after] == "\t" else { return nil }
                    return KeySplit(key: text[text.startIndex..<next], afterColon: after)
                }
                index = text.index(after: index)
            }
            return nil
        }
        if "[{#|>%@`,]}".contains(first) || text.hasPrefix("? ") { return nil }

        var index = text.startIndex
        var previous: Character = " "
        while index < text.endIndex {
            let ch = text[index]
            if ch == "#", previous == " " || previous == "\t" { return nil }
            if ch == ":" {
                let after = text.index(after: index)
                if after == text.endIndex || text[after] == " " || text[after] == "\t" {
                    let key = text[text.startIndex..<index]
                    guard !key.isEmpty else { return nil }
                    return KeySplit(key: key, afterColon: after)
                }
            }
            previous = ch
            index = text.index(after: index)
        }
        return nil
    }

    /// What the clipboard heuristic accepts as a key: quoted, or a single short
    /// word. `first name: Ada` is valid YAML but too close to prose to claim.
    static func isSimpleKey(_ key: Substring) -> Bool {
        if key.first == "\"" || key.first == "'" { return true }
        return key.count <= 64 && !key.contains(where: { $0 == " " || $0 == "\t" })
    }

    // MARK: - Scalars

    static func classify(_ scalar: String) -> SyntaxToken.Kind {
        switch scalar {
        case "null", "Null", "NULL", "~": return .null
        case "true", "True", "TRUE", "false", "False", "FALSE": return .bool
        case ".inf", ".Inf", ".INF", "+.inf", "-.inf", "-.Inf", "-.INF",
             ".nan", ".NaN", ".NAN": return .number
        default: break
        }
        guard let first = scalar.first, first.isASCII,
              first.isNumber || first == "-" || first == "+" || first == "." else { return .string }
        if scalar.hasPrefix("0o"), scalar.dropFirst(2).allSatisfy({ ("0"..."7").contains($0) }),
           scalar.count > 2 { return .number }
        if scalar.hasPrefix("0x"), scalar.dropFirst(2).allSatisfy(\.isHexDigit), scalar.count > 2 {
            return .number
        }
        if scalar.contains(where: \.isNumber), scalar.allSatisfy({ $0.isASCII && ($0.isNumber || "+-.eE".contains($0)) }),
           Double(scalar) != nil { return .number }
        return .string
    }

    // MARK: - Value scanner

    /// What carries from one line to the next while a value is still open.
    struct ScanState {
        var flowDepth = 0
        var openQuote: Character?
        var openedOnLine = 0

        var isOpen: Bool { flowDepth > 0 || openQuote != nil }
    }

    /// Finds the end of a quoted scalar starting at `start` (just past the
    /// opening quote): a backslash escapes in double quotes, and a doubled
    /// quote is the escape in single quotes. Returns where the scan stopped —
    /// just past the closing quote, or the end of the line when it is still
    /// open — and whether it closed.
    static func scanQuoted(_ chars: [Character], from start: Int,
                           quote: Character) -> (end: Int, closed: Bool) {
        var j = start
        while j < chars.count {
            if quote == "\"", chars[j] == "\\" { j += 2; continue }
            if chars[j] == quote {
                if quote == "'", j + 1 < chars.count, chars[j + 1] == "'" { j += 2; continue }
                return (j + 1, true)
            }
            j += 1
        }
        return (chars.count, false)
    }

    /// Tokenizes the text after a key or dash: anchors, tags, quoted strings,
    /// flow collections, comments and plain scalars.
    static func scanValue(_ text: Substring, state: inout ScanState, line: Int,
                          isFirstOnLine: Bool = true) -> [SyntaxToken] {
        var out: [SyntaxToken] = []
        let chars = Array(text)
        var i = 0
        var atItemStart = isFirstOnLine
        var seenValueToken = false

        func put(_ kind: SyntaxToken.Kind, _ s: String) {
            guard !s.isEmpty else { return }
            out.append(SyntaxToken(kind: kind, text: s))
        }

        while i < chars.count {
            // A quote left open by an earlier line is closed first.
            if let quote = state.openQuote {
                let (j, closed) = scanQuoted(chars, from: i, quote: quote)
                put(.string, String(chars[i..<j]))
                i = j
                if closed { state.openQuote = nil; seenValueToken = true; atItemStart = false }
                continue
            }

            let ch = chars[i]
            if ch == " " || ch == "\t" {
                var j = i
                while j < chars.count, chars[j] == " " || chars[j] == "\t" { j += 1 }
                put(.whitespace, String(chars[i..<j]))
                i = j
                continue
            }
            if ch == "#", i == 0 || chars[i - 1] == " " || chars[i - 1] == "\t" {
                put(.comment, String(chars[i...]))
                i = chars.count
                continue
            }
            if atItemStart, ch == "&" || ch == "*" || ch == "!" {
                var j = i + 1
                while j < chars.count, chars[j] != " ", chars[j] != "\t",
                      !(state.flowDepth > 0 && ",]}".contains(chars[j])) { j += 1 }
                put(.attributeName, String(chars[i..<j]))
                i = j
                continue
            }
            if atItemStart, !seenValueToken, state.flowDepth == 0, ch == "|" || ch == ">" {
                var j = i + 1
                while j < chars.count, "+-0123456789".contains(chars[j]) { j += 1 }
                if j == chars.count || chars[j] == " " || chars[j] == "\t" {
                    put(.punctuation, String(chars[i..<j]))
                    i = j
                    seenValueToken = true
                    continue
                }
            }
            if ch == "\"" || ch == "'", atItemStart {
                state.openQuote = ch
                state.openedOnLine = line
                put(.string, String(ch))
                i += 1
                // Left open, the branch above finishes it on a later line.
                let (j, closed) = scanQuoted(chars, from: i, quote: ch)
                let body = String(chars[i..<j])
                // In a flow mapping a quoted word before a colon is a key.
                var isKey = false
                if closed, state.flowDepth > 0 {
                    var k = j
                    while k < chars.count, chars[k] == " " { k += 1 }
                    isKey = k < chars.count && chars[k] == ":"
                }
                put(isKey ? .key : .string, body)
                i = j
                if closed { state.openQuote = nil }
                atItemStart = false
                seenValueToken = true
                continue
            }
            if atItemStart, ch == "[" || ch == "{" {
                state.flowDepth += 1
                state.openedOnLine = line
                put(.punctuation, String(ch))
                i += 1
                seenValueToken = true
                continue
            }
            if state.flowDepth > 0, ch == "]" || ch == "}" {
                state.flowDepth -= 1
                put(.punctuation, String(ch))
                i += 1
                atItemStart = false
                continue
            }
            if state.flowDepth > 0, ch == "," {
                put(.punctuation, ",")
                i += 1
                atItemStart = true
                continue
            }
            if state.flowDepth > 0, ch == ":" {
                put(.punctuation, ":")
                i += 1
                atItemStart = true
                continue
            }

            // Plain scalar.
            var j = i
            while j < chars.count {
                let c = chars[j]
                if c == "#", j > i, chars[j - 1] == " " || chars[j - 1] == "\t" { break }
                if state.flowDepth > 0, ",[]{}".contains(c) { break }
                if c == ":", state.flowDepth > 0 {
                    let next = j + 1 < chars.count ? chars[j + 1] : " "
                    if next == " " || next == "\t" || ",]}".contains(next) { break }
                }
                j += 1
            }
            var end = j
            while end > i, chars[end - 1] == " " || chars[end - 1] == "\t" { end -= 1 }
            let scalar = String(chars[i..<end])
            var isKey = false
            if state.flowDepth > 0 {
                var k = end
                while k < chars.count, chars[k] == " " { k += 1 }
                isKey = k < chars.count && chars[k] == ":"
            }
            put(isKey ? .key : classify(scalar), scalar)
            put(.whitespace, String(chars[end..<j]))
            i = j
            atItemStart = false
            seenValueToken = true
        }
        return out
    }

    // MARK: - Line walk

    private struct Level {
        let src: Int
        let out: Int
    }

    private struct Run {
        let width: Int
        var sink: TokenSink

        var stack: [Level] = []
        var scan = ScanState()
        /// Set while inside a `|` or `>` block: the key's own column, where
        /// the content has to be indented past.
        var blockOwnerSrc: Int?
        var blockOut = 0
        var blockSrcIndent: Int?
        /// The most recent key line, so a deeper line after a plain value reads
        /// as that value continuing rather than a new level.
        var lastOwnerSrc = 0
        var lastOwnerOut = 0
        var lastHadInlineValue = false
        var hasEmitted = false

        init(width: Int, limit: Int) {
            self.width = width
            self.sink = TokenSink(limit: limit)
        }

        mutating func emit(_ kind: SyntaxToken.Kind, _ text: String) {
            guard !text.isEmpty else { return }
            sink.append(kind, text)
        }

        mutating func emit(_ batch: [SyntaxToken]) {
            for token in batch { emit(token.kind, token.text) }
        }

        mutating func newline() {
            if hasEmitted { emit(.whitespace, "\n") }
            hasEmitted = true
        }

        func pad(_ columns: Int) -> String { String(repeating: " ", count: max(0, columns)) }

        mutating func finish() throws {
            if scan.isOpen {
                throw YAMLFormatError(reason: "Unterminated quote or bracket", line: scan.openedOnLine)
            }
        }

        mutating func consume(_ rawLine: Substring, number: Int) throws {
            let leading = rawLine.prefix(while: { $0 == " " || $0 == "\t" })
            let n = leading.count
            let rest = rawLine.dropFirst(n)
            let body = rest.trimmingTrailingSpaces()
            let isBlank = body.isEmpty

            // Block scalar content keeps its text and its own relative indent.
            if let owner = blockOwnerSrc {
                if isBlank {
                    newline()
                    return
                }
                if n > owner {
                    if blockSrcIndent == nil { blockSrcIndent = n }
                    let relative = max(0, n - (blockSrcIndent ?? n))
                    newline()
                    emit(.whitespace, pad(blockOut + relative))
                    emit(.string, String(rest))
                    return
                }
                blockOwnerSrc = nil
                blockSrcIndent = nil
            }

            if isBlank {
                newline()
                return
            }
            if leading.contains("\t") {
                throw YAMLFormatError(reason: "Tabs can't indent YAML", line: number)
            }

            // A quote or bracket still open from an earlier line.
            if scan.isOpen {
                newline()
                emit(.whitespace, pad(lastOwnerOut + width))
                emit(YAMLFormatter.scanValue(body, state: &scan, line: number, isFirstOnLine: false))
                return
            }

            if body.first == "#" {
                // Free-floating comment: aligned to the level it sits at.
                let level = stack.last(where: { $0.src <= n })
                let out = level.map { $0.src == n ? $0.out : $0.out + width } ?? 0
                newline()
                emit(.whitespace, pad(out))
                emit(.comment, String(body))
                return
            }

            if n == 0 {
                if body == "---" || body.hasPrefix("--- ") || body == "..." {
                    stack = []
                    lastHadInlineValue = false
                    newline()
                    let marker = body.prefix(while: { $0 != " " })
                    emit(.punctuation, String(marker))
                    let remainder = body.dropFirst(marker.count)
                    if !remainder.isEmpty {
                        emit(YAMLFormatter.scanValue(remainder, state: &scan, line: number, isFirstOnLine: true))
                    }
                    return
                }
                if body.first == "%" {
                    newline()
                    emit(.comment, String(body))
                    return
                }
            }

            // A deeper line after `key: value` is the value carrying on.
            if lastHadInlineValue, n > lastOwnerSrc {
                newline()
                emit(.whitespace, pad(lastOwnerOut + width))
                emit(YAMLFormatter.scanValue(body, state: &scan, line: number, isFirstOnLine: false))
                return
            }

            // Which level is this line on?
            var popped = false
            while let top = stack.last, top.src > n {
                stack.removeLast()
                popped = true
            }
            var out: Int
            if let top = stack.last {
                if top.src == n {
                    out = top.out
                } else if popped {
                    throw YAMLFormatError(reason: "Indentation doesn't match any level above", line: number)
                } else {
                    out = top.out + width
                    stack.append(Level(src: n, out: out))
                }
            } else if popped {
                throw YAMLFormatError(reason: "Indentation doesn't match any level above", line: number)
            } else {
                out = 0
                stack.append(Level(src: n, out: 0))
            }

            newline()
            emit(.whitespace, pad(out))

            // Dashes: each opens a level for whatever follows it on the line.
            var text = body
            var col = n
            var ownerSrc = n
            var ownerOut = out
            var dashed = false
            while text == "-" || text.hasPrefix("- ") {
                dashed = true
                emit(.punctuation, "-")
                let gap = text.dropFirst().prefix(while: { $0 == " " }).count
                text = text.dropFirst(1 + gap)
                ownerSrc = col
                ownerOut = out
                if text.isEmpty { break }
                emit(.whitespace, " ")
                col += 1 + gap
                out += 2
                stack.append(Level(src: col, out: out))
                ownerSrc = col
                ownerOut = out
            }
            lastHadInlineValue = false
            if text.isEmpty {
                lastOwnerSrc = ownerSrc
                lastOwnerOut = ownerOut
                return
            }

            // A plain value after a dash continues on any line indented past
            // the dash; one after a key, only past the key's own column.
            let split = YAMLFormatter.splitKey(text)
            lastOwnerSrc = dashed && split == nil ? ownerSrc - 1 : ownerSrc
            lastOwnerOut = ownerOut

            if let split {
                let key = text[text.startIndex..<split.afterColon].dropLast()
                emit(.key, String(key))
                emit(.punctuation, ":")
                let value = text[split.afterColon...]
                let tokensForValue = YAMLFormatter.scanValue(value, state: &scan, line: number)
                emit(tokensForValue)
                noteValue(tokensForValue, ownerSrc: ownerSrc)
            } else {
                let tokensForValue = YAMLFormatter.scanValue(text, state: &scan, line: number)
                emit(tokensForValue)
                lastHadInlineValue = tokensForValue.contains(where: Self.isMeaningful) && !scan.isOpen
            }
        }

        /// A value token, as opposed to spacing, a comment, or an anchor or tag
        /// that only labels what follows on the next lines.
        static func isMeaningful(_ token: SyntaxToken) -> Bool {
            ![.whitespace, .comment, .attributeName].contains(token.kind)
        }

        /// After a key: is there a real value on the line, and does it open a
        /// block scalar.
        mutating func noteValue(_ value: [SyntaxToken], ownerSrc: Int) {
            let meaningful = value.filter(Self.isMeaningful)
            if let first = meaningful.first, first.kind == .punctuation, first.text.first == "|" || first.text.first == ">" {
                blockOwnerSrc = ownerSrc
                blockOut = lastOwnerOut + width
                blockSrcIndent = nil
                lastHadInlineValue = false
                return
            }
            lastHadInlineValue = !meaningful.isEmpty && !scan.isOpen
        }
    }
}

private extension Substring {
    func trimmingTrailingSpaces() -> Substring {
        var end = endIndex
        while end > startIndex, self[index(before: end)] == " " || self[index(before: end)] == "\t" {
            end = index(before: end)
        }
        return self[startIndex..<end]
    }
}
