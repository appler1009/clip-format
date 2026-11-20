import Foundation

/// Formats `XMLValue` into the same token stream the JSON printer produces, so
/// both hosts render XML through the code they already had.
public enum XMLPrinter {
    public static func tokens(for nodes: [XMLValue], indent: Int,
                              characterLimit: Int = .max) -> (tokens: [SyntaxToken], isTruncated: Bool) {
        var sink = TokenSink(limit: characterLimit)
        let significant = nodes.filter { !$0.isInsignificantWhitespace }
        for (offset, node) in significant.enumerated() {
            if sink.isTruncated { break }
            if offset > 0 { sink.append(.whitespace, "\n") }
            emit(node, indent: indent, level: 0, into: &sink)
        }
        return sink.finish()
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

    private static func emit(_ node: XMLValue, indent: Int, level: Int, into sink: inout TokenSink) {
        guard !sink.isTruncated else { return }
        let pad = String(repeating: " ", count: indent * level)

        func put(_ kind: SyntaxToken.Kind, _ text: String) {
            sink.append(kind, text)
        }

        switch node {
        case .text(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            put(.whitespace, pad)
            put(.text, escapeMarkup(trimmed))

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
                put(.string, "\"\(escapeMarkup(attribute.value))\"")
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
                put(.text, escapeMarkup(value.trimmingCharacters(in: .whitespacesAndNewlines)))
            } else {
                for child in significant {
                    if sink.isTruncated { return }
                    put(.whitespace, "\n")
                    emit(child, indent: indent, level: level + 1, into: &sink)
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
            out += escapeMarkup(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case .comment(let value):
            out += "<!--\(value)-->"
        case .processingInstruction(let target, let data):
            out += "<?\(target)\(data.map { $0.isEmpty ? "" : " \($0)" } ?? "")?>"
        case .element(let name, let attributes, let children):
            out += "<\(name)"
            for attribute in attributes { out += " \(attribute.name)=\"\(escapeMarkup(attribute.value))\"" }
            let significant = children.filter { !$0.isInsignificantWhitespace }
            guard !significant.isEmpty else { out += "/>"; return }
            out += ">"
            for child in significant { emitMinified(child, into: &out) }
            out += "</\(name)>"
        }
    }
}
