import Foundation

/// A parsed XML node.
///
/// Attributes keep their source order, for the same reason object members do:
/// a formatter that reshuffles them is useless for reading a document you just
/// copied. `XMLParser`, the SAX API, hands attributes over as a dictionary and
/// loses that, which is why this is built on `XMLDocument`.
public indirect enum XMLValue: Equatable, Sendable {
    case element(name: String, attributes: [(name: String, value: String)], children: [XMLValue])
    case text(String)
    case comment(String)
    case processingInstruction(target: String, data: String?)

    public static func == (lhs: XMLValue, rhs: XMLValue) -> Bool {
        switch (lhs, rhs) {
        case let (.element(ln, la, lc), .element(rn, ra, rc)):
            return ln == rn && lc == rc && la.count == ra.count
                && zip(la, ra).allSatisfy { $0.name == $1.name && $0.value == $1.value }
        case let (.text(a), .text(b)): return a == b
        case let (.comment(a), .comment(b)): return a == b
        case let (.processingInstruction(lt, ld), .processingInstruction(rt, rd)):
            return lt == rt && ld == rd
        default: return false
        }
    }

    /// A text node holding nothing but the source's own indentation, which the
    /// printer replaces with its own.
    var isInsignificantWhitespace: Bool {
        if case .text(let value) = self {
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }
}

public struct XMLParseError: Error, Equatable, Sendable {
    public let reason: String
    public var message: String { reason }
}

/// Reads XML into `XMLValue`.
///
/// Built on `XMLDocument`, which keeps attribute order and is strict about
/// well-formedness — no error recovery, and no second root element. A formatter
/// that silently repaired its input would teach you nothing about the file in
/// front of you.
public enum XMLReader {
    public static func parse(_ text: String) throws -> [XMLValue] {
        let document: XMLDocument
        do {
            // Never resolve external entities: this runs on a document that
            // arrived from the clipboard or someone else's file, and fetching
            // whatever its DTD points at is not part of formatting it.
            document = try XMLDocument(xmlString: text,
                                       options: [.nodePreserveWhitespace, .nodeLoadExternalEntitiesNever])
        } catch {
            throw XMLParseError(reason: Self.reason(from: error))
        }

        var nodes = (document.children ?? []).compactMap(Self.value(from:))
        // `XMLDocument` does not expose the declaration as a node, and its
        // `version` / `characterEncoding` read "1.0" and "UTF-8" whether or not
        // the source had one — so it is taken from the source text instead,
        // and echoed exactly as written rather than reconstructed.
        if let declaration = Self.declaration(in: text) {
            nodes.insert(declaration, at: 0)
        }
        guard nodes.contains(where: { if case .element = $0 { return true } else { return false } }) else {
            throw XMLParseError(reason: "No XML elements")
        }
        return nodes
    }

    private static func declaration(in text: String) -> XMLValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<?xml"), let close = trimmed.range(of: "?>") else { return nil }
        let body = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 5)..<close.lowerBound]
        return .processingInstruction(target: "xml",
                                      data: body.trimmingCharacters(in: .whitespaces))
    }

    /// `XMLDocument`'s errors read like "Error Domain=NSXMLParserErrorDomain
    /// Code=76 …" unless the underlying message is pulled out.
    private static func reason(from error: Error) -> String {
        let nsError = error as NSError
        if let detail = nsError.userInfo[NSLocalizedDescriptionKey] as? String, !detail.isEmpty {
            return detail.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "Not XML"
    }

    private static func value(from node: XMLNode) -> XMLValue? {
        switch node.kind {
        case .element:
            guard let element = node as? XMLElement, let name = element.name else { return nil }
            // Namespace declarations are not in `attributes` — dropping them
            // would silently rewrite the document — so they are put back, in
            // front, where they are conventionally written.
            let namespaces = (element.namespaces ?? []).map { namespace -> (name: String, value: String) in
                let prefix = namespace.name ?? ""
                return (name: prefix.isEmpty ? "xmlns" : "xmlns:\(prefix)",
                        value: namespace.stringValue ?? "")
            }
            let attributes = namespaces + (element.attributes ?? []).compactMap { attribute -> (name: String, value: String)? in
                guard let name = attribute.name else { return nil }
                return (name: name, value: attribute.stringValue ?? "")
            }
            return .element(name: name,
                            attributes: attributes,
                            children: (element.children ?? []).compactMap(Self.value(from:)))
        case .text:
            return .text(node.stringValue ?? "")
        case .comment:
            return .comment(node.stringValue ?? "")
        case .processingInstruction:
            return .processingInstruction(target: node.name ?? "", data: node.stringValue)
        default:
            // DTDs and namespace nodes are structure this formatter does not
            // render; dropping them keeps the output to what is on the page.
            return nil
        }
    }
}
