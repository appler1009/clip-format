import Foundation

/// One classified run of characters in formatted output. Both renderers (HTML
/// for Quick Look, `AttributedString` for the popover) consume this same stream,
/// which is what keeps the two hosts visually identical.
public struct JSONToken: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case punctuation
        case key
        case string
        case number
        case bool
        case null
        case whitespace
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
    public static func tokens(for value: JSONValue, indent: Int) -> [JSONToken] {
        var tokens: [JSONToken] = []
        emit(value, indent: indent, level: 0, into: &tokens)
        return tokens
    }

    /// Formats `value` as indented plain text.
    public static func pretty(_ value: JSONValue, indent: Int) -> String {
        tokens(for: value, indent: indent).map(\.text).joined()
    }

    /// Formats `value` with no insignificant whitespace.
    public static func minified(_ value: JSONValue) -> String {
        var out = ""
        emitMinified(value, into: &out)
        return out
    }

    private static func emit(_ value: JSONValue, indent: Int, level: Int, into tokens: inout [JSONToken]) {
        switch value {
        case .null:
            tokens.append(JSONToken(kind: .null, text: "null"))
        case .bool(let flag):
            tokens.append(JSONToken(kind: .bool, text: flag ? "true" : "false"))
        case .number(let literal):
            tokens.append(JSONToken(kind: .number, text: literal))
        case .string(let text):
            tokens.append(JSONToken(kind: .string, text: quote(text)))
        case .array(let elements):
            guard !elements.isEmpty else {
                tokens.append(JSONToken(kind: .punctuation, text: "[]"))
                return
            }
            tokens.append(JSONToken(kind: .punctuation, text: "["))
            for (offset, element) in elements.enumerated() {
                if offset > 0 { tokens.append(JSONToken(kind: .punctuation, text: ",")) }
                newline(indent: indent, level: level + 1, into: &tokens)
                emit(element, indent: indent, level: level + 1, into: &tokens)
            }
            newline(indent: indent, level: level, into: &tokens)
            tokens.append(JSONToken(kind: .punctuation, text: "]"))
        case .object(let members):
            guard !members.isEmpty else {
                tokens.append(JSONToken(kind: .punctuation, text: "{}"))
                return
            }
            tokens.append(JSONToken(kind: .punctuation, text: "{"))
            for (offset, member) in members.enumerated() {
                if offset > 0 { tokens.append(JSONToken(kind: .punctuation, text: ",")) }
                newline(indent: indent, level: level + 1, into: &tokens)
                tokens.append(JSONToken(kind: .key, text: quote(member.key)))
                tokens.append(JSONToken(kind: .punctuation, text: ":"))
                tokens.append(JSONToken(kind: .whitespace, text: " "))
                emit(member.value, indent: indent, level: level + 1, into: &tokens)
            }
            newline(indent: indent, level: level, into: &tokens)
            tokens.append(JSONToken(kind: .punctuation, text: "}"))
        }
    }

    private static func newline(indent: Int, level: Int, into tokens: inout [JSONToken]) {
        tokens.append(JSONToken(kind: .whitespace, text: "\n" + String(repeating: " ", count: indent * level)))
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
