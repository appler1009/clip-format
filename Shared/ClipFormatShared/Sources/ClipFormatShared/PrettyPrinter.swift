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
        var sink = TokenSink(limit: characterLimit, reserve: min(256, max(16, characterLimit / 8)))
        emit(value, indent: indent, level: 0, into: &sink)
        return sink.finish()
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

    /// Shared with JSON Lines, which prints every record into one sink.
    static func emit(_ value: JSONValue, indent: Int, level: Int, into sink: inout TokenSink) {
        guard !sink.isTruncated else { return }

        func newline(_ level: Int) {
            sink.append(.whitespace, "\n" + String(repeating: " ", count: indent * level))
        }

        switch value {
        case .null:
            sink.append(.null, "null")
        case .bool(let flag):
            sink.append(.bool, flag ? "true" : "false")
        case .number(let literal):
            sink.append(.number, literal)
        case .string(let text):
            sink.append(.string, quote(text))
        case .array(let elements):
            guard !elements.isEmpty else {
                sink.append(.punctuation, "[]")
                return
            }
            sink.append(.punctuation, "[")
            for (offset, element) in elements.enumerated() {
                if sink.isTruncated { return }
                if offset > 0 { sink.append(.punctuation, ",") }
                newline(level + 1)
                emit(element, indent: indent, level: level + 1, into: &sink)
            }
            newline(level)
            sink.append(.punctuation, "]")
        case .object(let members):
            guard !members.isEmpty else {
                sink.append(.punctuation, "{}")
                return
            }
            sink.append(.punctuation, "{")
            for (offset, member) in members.enumerated() {
                if sink.isTruncated { return }
                if offset > 0 { sink.append(.punctuation, ",") }
                newline(level + 1)
                sink.append(.key, quote(member.key))
                sink.append(.punctuation, ":")
                sink.append(.whitespace, " ")
                emit(member.value, indent: indent, level: level + 1, into: &sink)
            }
            newline(level)
            sink.append(.punctuation, "}")
        }
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
