import Foundation

/// Collects a printer's tokens up to a character budget.
///
/// Every printer (JSON, XML, YAML) stops at the same point and ends with the
/// same notice, so the budget lives here rather than in each of them. Once a
/// token would cross the limit nothing more is taken, and `finish()` appends
/// the "… truncated" line.
struct TokenSink {
    let limit: Int
    private(set) var tokens: [SyntaxToken] = []
    /// Characters taken so far.
    private(set) var count = 0
    private(set) var isTruncated = false

    init(limit: Int, reserve: Int = 64) {
        self.limit = limit
        tokens.reserveCapacity(reserve)
    }

    mutating func append(_ kind: SyntaxToken.Kind, _ text: String) {
        guard !isTruncated else { return }
        let next = count + text.count
        guard next <= limit else {
            isTruncated = true
            return
        }
        count = next
        tokens.append(SyntaxToken(kind: kind, text: text))
    }

    /// The tokens, with the truncation notice when the budget ran out.
    consuming func finish() -> (tokens: [SyntaxToken], isTruncated: Bool) {
        if isTruncated {
            tokens.append(SyntaxToken(kind: .whitespace, text: "\n"))
            tokens.append(SyntaxToken(kind: .punctuation, text: "… truncated"))
        }
        return (tokens, isTruncated)
    }
}

/// Escapes text for HTML or XML output. The reader resolves entities and the
/// HTML renderer receives plain token text, so both put the escapes back the
/// same way.
func escapeMarkup(_ text: String) -> String {
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
