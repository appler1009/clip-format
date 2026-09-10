import Foundation

/// Formats `XMLValue` into the same token stream the JSON printer produces, so
/// both hosts render XML through the code they already had.
public enum XMLPrinter {
    public static func tokens(for nodes: [XMLValue], indent: Int,
                              characterLimit: Int = .max) -> (tokens: [SyntaxToken], isTruncated: Bool) {
        var tokens: [SyntaxToken] = []
        tokens.reserveCapacity(64)
        var count = 0
        var truncated = false
        let significant = nodes.filter { !$0.isInsignificantWhitespace }
        for (offset, node) in significant.enumerated() {
            if truncated { break }
            if offset > 0 { append(.whitespace, "\n", limit: characterLimit, count: &count, truncated: &truncated, into: &tokens) }
            emit(node, indent: indent, level: 0, limit: characterLimit,
                 count: &count, truncated: &truncated, into: &tokens)
        }
        if truncated {
            tokens.append(SyntaxToken(kind: .whitespace, text: "\n"))
            tokens.append(SyntaxToken(kind: .punctuation, text: "… truncated"))
        }
        return (tokens, truncated)
    }

    public static func pretty(_ nodes: [XMLValue], indent: Int) -> String {
        tokens(for: nodes, indent: indent).tokens.map(\.text).joined()
    }

    /// One line, with the whitespace between elements dropped. Text inside an
    /// element is trimmed at its edges, as the formatted view trims it — see
    /// the README's note about `xml:space="preserve"`.
    public static func minified(_ nodes: [XMLValue]) -> String {
        var out = ""
        out.reserveCapacity(64)
        for node in nodes where !node.isInsignificantWhitespace {
            emitMinified(node, into: &out)
        }
        return out
    }

    private static func append(_ kind: SyntaxToken.Kind, _ text: String, limit: Int,
                               count: inout Int, truncated: inout Bool,
                               into tokens: inout [SyntaxToken]) {
        guard !truncated else { return }
        let next = count + text.count
        if next > limit {
            truncated = true
            return
        }
        count = next
        tokens.append(SyntaxToken(kind: kind, text: text))
    }

    private static func emit(_ node: XMLValue, indent: Int, level: Int, limit: Int,
                             count: inout Int, truncated: inout Bool,
                             into tokens: inout [SyntaxToken]) {
        guard !truncated else { return }
        let pad = String(repeating: " ", count: indent * level)

        func put(_ kind: SyntaxToken.Kind, _ text: String) {
            append(kind, text, limit: limit, count: &count, truncated: &truncated, into: &tokens)
        }

        switch node {
        case .text(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            put(.whitespace, pad)
            put(.text, escape(trimmed))

        case .comment(let value):
            put(.whitespace, pad)
            put(.comment, "<!--\(value)-->")

        case .processingInstruction(let target, let data):
            put(.whitespace, pad)
            put(.punctuation, "<?")
            put(.tagName, target)
            if let data, !data.isEmpty {
                put(.whitespace, " ")
                put(.attributeName, data)
            }
            put(.punctuation, "?>")

        case .element(let name, let attributes, let children):
            put(.whitespace, pad)
            put(.punctuation, "<")
            put(.tagName, name)
            for attribute in attributes {
                put(.whitespace, " ")
                put(.attributeName, attribute.name)
                put(.punctuation, "=")
                put(.string, "\"\(escape(attribute.value))\"")
            }

            let significant = children.filter { !$0.isInsignificantWhitespace }
            guard !significant.isEmpty else {
                put(.punctuation, "/>")
                return
            }
            put(.punctuation, ">")

            // An element holding only text stays on one line: <title>Hi</title>
            // reads worse broken across three.
            if significant.count == 1, case .text(let value) = significant[0] {
                put(.text, escape(value.trimmingCharacters(in: .whitespacesAndNewlines)))
            } else {
                for child in significant {
                    if truncated { return }
                    put(.whitespace, "\n")
                    emit(child, indent: indent, level: level + 1, limit: limit,
                         count: &count, truncated: &truncated, into: &tokens)
                }
                put(.whitespace, "\n" + pad)
            }
            put(.punctuation, "</")
            put(.tagName, name)
            put(.punctuation, ">")
        }
    }

    private static func emitMinified(_ node: XMLValue, into out: inout String) {
        switch node {
        case .text(let value):
            out += escape(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case .comment(let value):
            out += "<!--\(value)-->"
        case .processingInstruction(let target, let data):
            out += "<?\(target)\(data.map { $0.isEmpty ? "" : " \($0)" } ?? "")?>"
        case .element(let name, let attributes, let children):
            out += "<\(name)"
            for attribute in attributes { out += " \(attribute.name)=\"\(escape(attribute.value))\"" }
            let significant = children.filter { !$0.isInsignificantWhitespace }
            guard !significant.isEmpty else { out += "/>"; return }
            out += ">"
            for child in significant { emitMinified(child, into: &out) }
            out += "</\(name)>"
        }
    }

    /// The reader resolves entities, so text arriving here is the real
    /// characters; putting it back into a document means escaping again.
    private static func escape(_ text: String) -> String {
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
