import Foundation

/// One classified run of characters in formatted output. Both renderers (HTML
/// for Quick Look, `AttributedString` for the popover) consume this same stream,
/// which is what keeps the two hosts visually identical.
public struct SyntaxToken: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case punctuation
        case key
        case string
        case number
        case bool
        case null
        case whitespace
        // XML. Element and attribute names sit where object keys do, but text
        // content and comments have no JSON equivalent and need their own
        // colours.
        case tagName
        case attributeName
        case text
        case comment
    }

    public let kind: Kind
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public enum PrettyPrinter {
    /// Formats `value` as an indented token stream.
    ///
    /// Pass `characterLimit` to stop once the printed length would exceed it —
    /// callers that only show a preview (the popover / Quick Look) use this so
    /// a multi‑megabyte tree never materialises a full token array first.
    public static func tokens(for value: JSONValue, indent: Int,
                              characterLimit: Int = .max) -> (tokens: [SyntaxToken], isTruncated: Bool) {
        var tokens: [SyntaxToken] = []
        tokens.reserveCapacity(min(256, max(16, characterLimit / 8)))
        var count = 0
        var truncated = false
        emit(value, indent: indent, level: 0, limit: characterLimit,
             count: &count, truncated: &truncated, into: &tokens)
        if truncated {
            tokens.append(SyntaxToken(kind: .whitespace, text: "\n"))
            tokens.append(SyntaxToken(kind: .punctuation, text: "… truncated"))
        }
        return (tokens, truncated)
    }

    /// Formats `value` as indented plain text.
    public static func pretty(_ value: JSONValue, indent: Int) -> String {
        tokens(for: value, indent: indent).tokens.map(\.text).joined()
    }

    /// Formats `value` with no insignificant whitespace.
    public static func minified(_ value: JSONValue) -> String {
        var out = ""
        out.reserveCapacity(64)
        emitMinified(value, into: &out)
        return out
    }

    private static func emit(_ value: JSONValue, indent: Int, level: Int, limit: Int,
                             count: inout Int, truncated: inout Bool,
                             into tokens: inout [SyntaxToken]) {
        guard !truncated else { return }

        func append(_ kind: SyntaxToken.Kind, _ text: String) {
            guard !truncated else { return }
            let next = count + text.count
            if next > limit {
                truncated = true
                return
            }
            count = next
            tokens.append(SyntaxToken(kind: kind, text: text))
        }

        switch value {
        case .null:
            append(.null, "null")
        case .bool(let flag):
            append(.bool, flag ? "true" : "false")
        case .number(let literal):
            append(.number, literal)
        case .string(let text):
            append(.string, quote(text))
        case .array(let elements):
            guard !elements.isEmpty else {
                append(.punctuation, "[]")
                return
            }
            append(.punctuation, "[")
            for (offset, element) in elements.enumerated() {
                if truncated { return }
                if offset > 0 { append(.punctuation, ",") }
                newline(indent: indent, level: level + 1, append: append)
                emit(element, indent: indent, level: level + 1, limit: limit,
                     count: &count, truncated: &truncated, into: &tokens)
            }
            newline(indent: indent, level: level, append: append)
            append(.punctuation, "]")
        case .object(let members):
            guard !members.isEmpty else {
                append(.punctuation, "{}")
                return
            }
            append(.punctuation, "{")
            for (offset, member) in members.enumerated() {
                if truncated { return }
                if offset > 0 { append(.punctuation, ",") }
                newline(indent: indent, level: level + 1, append: append)
                append(.key, quote(member.key))
                append(.punctuation, ":")
                append(.whitespace, " ")
                emit(member.value, indent: indent, level: level + 1, limit: limit,
                     count: &count, truncated: &truncated, into: &tokens)
            }
            newline(indent: indent, level: level, append: append)
            append(.punctuation, "}")
        }
    }

    private static func newline(indent: Int, level: Int,
                                append: (SyntaxToken.Kind, String) -> Void) {
        append(.whitespace, "\n" + String(repeating: " ", count: indent * level))
    }

    private static func emitMinified(_ value: JSONValue, into out: inout String) {
        switch value {
        case .null: out += "null"
        case .bool(let flag): out += flag ? "true" : "false"
        case .number(let literal): out += literal
        case .string(let text): out += quote(text)
        case .array(let elements):
            out += "["
            for (offset, element) in elements.enumerated() {
                if offset > 0 { out += "," }
                emitMinified(element, into: &out)
            }
            out += "]"
        case .object(let members):
            out += "{"
            for (offset, member) in members.enumerated() {
                if offset > 0 { out += "," }
                out += quote(member.key)
                out += ":"
                emitMinified(member.value, into: &out)
            }
            out += "}"
        }
    }

    /// Re-encodes a Swift string as a JSON string literal. Non-ASCII stays
    /// literal — emoji and CJK read better than their \u escapes in a preview.
    static func quote(_ text: String) -> String {
        var out = "\""
        out.reserveCapacity(text.count + 2)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\u{00}"..."\u{1F}":
                out += String(format: "\\u%04x", scalar.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
