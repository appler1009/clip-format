import Foundation

/// A parsed JSON value.
///
/// Object members keep their source order — `JSONSerialization` hands back a
/// `Dictionary`, which does not, and a pretty printer that reshuffles keys is
/// useless for reading a payload you just copied.
public indirect enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    /// The number exactly as it appeared in the source, so `1.50` and `1e9`
    /// survive a round trip.
    case number(String)
    case string(String)
    case array([JSONValue])
    case object([(key: String, value: JSONValue)])

    /// An object or an array — what the hosts count as "some JSON", as
    /// opposed to a bare literal that happens to be valid.
    public var isContainer: Bool {
        switch self {
        case .object, .array: return true
        default: return false
        }
    }

    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case let (.bool(a), .bool(b)): return a == b
        case let (.number(a), .number(b)): return a == b
        case let (.string(a), .string(b)): return a == b
        case let (.array(a), .array(b)): return a == b
        case let (.object(a), .object(b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: return false
        }
    }
}

public struct JSONParseError: Error, Equatable, Sendable {
    /// UTF-16 offset into the source text where parsing stopped.
    public let offset: Int
    public let line: Int
    public let column: Int
    public let reason: String

    public var message: String { "\(reason) (line \(line), column \(column))" }
}

/// A small hand-rolled recursive-descent parser for RFC 8259 JSON.
public enum JSONParser {
    public struct Options: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// Accept `//` to end of line and `/* … */`, as JSONC and the JSON
        /// files tooling writes (`tsconfig.json`, VS Code settings) use. Off by
        /// default: RFC 8259 has no comments, and accepting them everywhere
        /// would make the strict reading a lie.
        public static let comments = Options(rawValue: 1 << 0)

        /// Accept a comma before the closing `}` or `]`. Tooling writes these
        /// next to comments — `tsconfig.json` has both — and a diff that adds
        /// one line should not have to touch the line above it.
        public static let trailingCommas = Options(rawValue: 1 << 1)

        /// What a `.jsonc` file is allowed: comments and trailing commas.
        public static let jsonc: Options = [.comments, .trailingCommas]
    }

    public static func parse(_ text: String, options: Options = []) throws -> JSONValue {
        var scanner = Scanner(Array(text.unicodeScalars), options: options)
        scanner.skipWhitespace()
        let value = try scanner.parseValue(depth: 0)
        scanner.skipWhitespace()
        guard !scanner.unterminatedBlockComment else {
            throw scanner.error("Unterminated block comment")
        }
        guard scanner.isAtEnd else {
            throw scanner.error("Unexpected trailing content")
        }
        return value
    }

    private static let maxDepth = 512

    struct Scanner {
        private let scalars: [Unicode.Scalar]
        private let options: Options
        private var index: Int = 0
        /// Set by `skipWhitespace`; `parse` turns it into an error.
        private(set) var unterminatedBlockComment = false

        init(_ scalars: [Unicode.Scalar], options: Options = []) {
            self.scalars = scalars
            self.options = options
        }

        var isAtEnd: Bool { index >= scalars.count }
        private var current: Unicode.Scalar? { isAtEnd ? nil : scalars[index] }

        func error(_ reason: String) -> JSONParseError {
            var line = 1, column = 1
            for scalar in scalars.prefix(index) {
                if scalar == "\n" { line += 1; column = 1 } else { column += 1 }
            }
            return JSONParseError(offset: index, line: line, column: column, reason: reason)
        }

        /// Whitespace, and comments when they are allowed. Every structural
        /// position in the grammar already calls this, which is what makes one
        /// change here enough to accept comments between any two tokens.
        mutating func skipWhitespace() {
            while true {
                while let c = current, c == " " || c == "\t" || c == "\n" || c == "\r" { index += 1 }
                guard options.contains(.comments), current == "/", index + 1 < scalars.count else { return }
                switch scalars[index + 1] {
                case "/":
                    index += 2
                    while let c = current, c != "\n", c != "\r" { index += 1 }
                case "*":
                    index += 2
                    var closed = false
                    while index + 1 < scalars.count {
                        if scalars[index] == "*" && scalars[index + 1] == "/" {
                            index += 2
                            closed = true
                            break
                        }
                        index += 1
                    }
                    if !closed {
                        // Recorded rather than thrown: skipWhitespace cannot
                        // throw without `try` at every structural position.
                        // `parse` checks this at the end, so an unclosed
                        // comment after a complete value is still an error
                        // instead of being swallowed as trivia.
                        index = scalars.count
                        unterminatedBlockComment = true
                    }
                default:
                    return // a lone '/' is the parser's problem, not ours
                }
            }
        }

        mutating func parseValue(depth: Int) throws -> JSONValue {
            guard depth <= JSONParser.maxDepth else { throw error("Nesting is too deep") }
            guard let c = current else { throw error("Unexpected end of input") }
            switch c {
            case "{": return try parseObject(depth: depth)
            case "[": return try parseArray(depth: depth)
            case "\"": return .string(try parseString())
            case "t": try expect("true"); return .bool(true)
            case "f": try expect("false"); return .bool(false)
            case "n": try expect("null"); return .null
            case "-", "0"..."9": return .number(try parseNumber())
            default: throw error("Unexpected character '\(c)'")
            }
        }

        private mutating func expect(_ literal: String) throws {
            for scalar in literal.unicodeScalars {
                guard current == scalar else { throw error("Invalid literal, expected '\(literal)'") }
                index += 1
            }
        }

        /// Consumes the comma, and reports whether the collection closed right
        /// after it. Whatever separates the two is skipped first, so the shape
        /// VS Code actually writes still parses:
        ///
        ///     "strict": true, // always
        ///     }
        ///
        /// Strict JSON never takes this path: the comma stands, and the next
        /// turn of the loop reports the missing member.
        private mutating func consumedTrailingComma(before close: Unicode.Scalar) -> Bool {
            index += 1 // ','
            guard options.contains(.trailingCommas) else { return false }
            skipWhitespace()
            guard current == close else { return false }
            index += 1
            return true
        }

        private mutating func parseObject(depth: Int) throws -> JSONValue {
            index += 1 // '{'
            var members: [(key: String, value: JSONValue)] = []
            skipWhitespace()
            if current == "}" { index += 1; return .object(members) }
            while true {
                skipWhitespace()
                guard current == "\"" else { throw error("Expected a quoted object key") }
                let key = try parseString()
                skipWhitespace()
                guard current == ":" else { throw error("Expected ':' after object key") }
                index += 1
                skipWhitespace()
                members.append((key, try parseValue(depth: depth + 1)))
                skipWhitespace()
                switch current {
                case ",":
                    if consumedTrailingComma(before: "}") { return .object(members) }
                case "}": index += 1; return .object(members)
                case nil: throw error("Unterminated object")
                default: throw error("Expected ',' or '}' in object")
                }
            }
        }

        private mutating func parseArray(depth: Int) throws -> JSONValue {
            index += 1 // '['
            var elements: [JSONValue] = []
            skipWhitespace()
            if current == "]" { index += 1; return .array(elements) }
            while true {
                skipWhitespace()
                elements.append(try parseValue(depth: depth + 1))
                skipWhitespace()
                switch current {
                case ",":
                    if consumedTrailingComma(before: "]") { return .array(elements) }
                case "]": index += 1; return .array(elements)
                case nil: throw error("Unterminated array")
                default: throw error("Expected ',' or ']' in array")
                }
            }
        }

        private mutating func parseString() throws -> String {
            index += 1 // opening quote
            var result = String.UnicodeScalarView()
            while true {
                guard let c = current else { throw error("Unterminated string") }
                index += 1
                switch c {
                case "\"":
                    return String(result)
                case "\\":
                    result.append(try parseEscape())
                case "\u{00}"..."\u{1F}":
                    throw error("Control character in string must be escaped")
                default:
                    result.append(c)
                }
            }
        }

        private mutating func parseEscape() throws -> Unicode.Scalar {
            guard let c = current else { throw error("Unterminated escape sequence") }
            index += 1
            switch c {
            case "\"": return "\""
            case "\\": return "\\"
            case "/": return "/"
            case "b": return "\u{08}"
            case "f": return "\u{0C}"
            case "n": return "\n"
            case "r": return "\r"
            case "t": return "\t"
            case "u":
                let first = try parseHexQuad()
                // A high surrogate must be followed by \uDC00–\uDFFF to form a scalar.
                if (0xD800...0xDBFF).contains(first) {
                    guard current == "\\", index + 1 < scalars.count, scalars[index + 1] == "u" else {
                        throw error("Unpaired UTF-16 high surrogate")
                    }
                    index += 2
                    let second = try parseHexQuad()
                    guard (0xDC00...0xDFFF).contains(second) else { throw error("Invalid UTF-16 surrogate pair") }
                    let combined = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
                    guard let scalar = Unicode.Scalar(combined) else { throw error("Invalid escaped code point") }
                    return scalar
                }
                guard let scalar = Unicode.Scalar(first), !(0xDC00...0xDFFF).contains(first) else {
                    throw error("Invalid escaped code point")
                }
                return scalar
            default:
                throw error("Unknown escape '\\\(c)'")
            }
        }

        private mutating func parseHexQuad() throws -> Int {
            var value = 0
            for _ in 0..<4 {
                guard let c = current, let digit = c.hexDigitValue else { throw error("Invalid \\u escape") }
                value = value << 4 | digit
                index += 1
            }
            return value
        }

        private mutating func parseNumber() throws -> String {
            let start = index
            if current == "-" { index += 1 }
            guard let first = current else { throw error("Unexpected end of number") }
            if first == "0" {
                index += 1
            } else if ("1"..."9").contains(first) {
                while let c = current, ("0"..."9").contains(c) { index += 1 }
            } else {
                throw error("Invalid number")
            }
            if current == "." {
                index += 1
                guard let c = current, ("0"..."9").contains(c) else { throw error("Expected a digit after '.'") }
                while let c = current, ("0"..."9").contains(c) { index += 1 }
            }
            if current == "e" || current == "E" {
                index += 1
                if current == "+" || current == "-" { index += 1 }
                guard let c = current, ("0"..."9").contains(c) else { throw error("Expected a digit in exponent") }
                while let c = current, ("0"..."9").contains(c) { index += 1 }
            }
            return String(String.UnicodeScalarView(scalars[start..<index]))
        }
    }
}

private extension Unicode.Scalar {
    var hexDigitValue: Int? { Character(self).hexDigitValue }
}
