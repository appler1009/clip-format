import Foundation

/// Formats `XMLValue` into the same token stream the JSON printer produces, so
/// both hosts render XML through the code they already had.
public enum XMLPrinter {
    public static func tokens(for nodes: [XMLValue], indent: Int) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        let significant = nodes.filter { !$0.isInsignificantWhitespace }
        for (offset, node) in significant.enumerated() {
            if offset > 0 { tokens.append(SyntaxToken(kind: .whitespace, text: "\n")) }
            emit(node, indent: indent, level: 0, into: &tokens)
        }
        return tokens
    }

    public static func pretty(_ nodes: [XMLValue], indent: Int) -> String {
        tokens(for: nodes, indent: indent).map(\.text).joined()
    }

    /// One line, with the whitespace between elements dropped. Text inside an
    /// element is trimmed at its edges, as the formatted view trims it — see
    /// the README's note about `xml:space="preserve"`.
    public static func minified(_ nodes: [XMLValue]) -> String {
        var out = ""
        for node in nodes where !node.isInsignificantWhitespace {
            emitMinified(node, into: &out)
        }
        return out
    }

    private static func emit(_ node: XMLValue, indent: Int, level: Int, into tokens: inout [SyntaxToken]) {
        let pad = String(repeating: " ", count: indent * level)
        switch node {
        case .text(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            tokens.append(SyntaxToken(kind: .whitespace, text: pad))
            tokens.append(SyntaxToken(kind: .text, text: escape(trimmed)))

        case .comment(let value):
            tokens.append(SyntaxToken(kind: .whitespace, text: pad))
            tokens.append(SyntaxToken(kind: .comment, text: "<!--\(value)-->"))

        case .processingInstruction(let target, let data):
            tokens.append(SyntaxToken(kind: .whitespace, text: pad))
            tokens.append(SyntaxToken(kind: .punctuation, text: "<?"))
            tokens.append(SyntaxToken(kind: .tagName, text: target))
            if let data, !data.isEmpty {
                tokens.append(SyntaxToken(kind: .whitespace, text: " "))
                tokens.append(SyntaxToken(kind: .attributeName, text: data))
            }
            tokens.append(SyntaxToken(kind: .punctuation, text: "?>"))

        case .element(let name, let attributes, let children):
            tokens.append(SyntaxToken(kind: .whitespace, text: pad))
            tokens.append(SyntaxToken(kind: .punctuation, text: "<"))
            tokens.append(SyntaxToken(kind: .tagName, text: name))
            for attribute in attributes {
                tokens.append(SyntaxToken(kind: .whitespace, text: " "))
                tokens.append(SyntaxToken(kind: .attributeName, text: attribute.name))
                tokens.append(SyntaxToken(kind: .punctuation, text: "="))
                tokens.append(SyntaxToken(kind: .string, text: "\"\(escape(attribute.value))\""))
            }

            let significant = children.filter { !$0.isInsignificantWhitespace }
            guard !significant.isEmpty else {
                tokens.append(SyntaxToken(kind: .punctuation, text: "/>"))
                return
            }
            tokens.append(SyntaxToken(kind: .punctuation, text: ">"))

            // An element holding only text stays on one line: <title>Hi</title>
            // reads worse broken across three.
            if significant.count == 1, case .text(let value) = significant[0] {
                tokens.append(SyntaxToken(kind: .text, text: escape(value.trimmingCharacters(in: .whitespacesAndNewlines))))
            } else {
                for child in significant {
                    tokens.append(SyntaxToken(kind: .whitespace, text: "\n"))
                    emit(child, indent: indent, level: level + 1, into: &tokens)
                }
                tokens.append(SyntaxToken(kind: .whitespace, text: "\n" + pad))
            }
            tokens.append(SyntaxToken(kind: .punctuation, text: "</"))
            tokens.append(SyntaxToken(kind: .tagName, text: name))
            tokens.append(SyntaxToken(kind: .punctuation, text: ">"))
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
