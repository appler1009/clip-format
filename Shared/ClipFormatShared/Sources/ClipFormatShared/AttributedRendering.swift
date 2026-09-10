import Foundation
import SwiftUI

public extension FormatCanvas {
    /// The popover's counterpart to `html(from:)` — same tokens, same theme.
    ///
    /// Neighbouring tokens of the same kind are coalesced into one
    /// `AttributedString` run (mirroring the HTML renderer) so a pretty-printed
    /// object does not allocate one piece per punctuation mark.
    ///
    /// When `showInvisibles` is on, spaces / tabs / line breaks become visible
    /// glyphs in the attributed string only. `prettyText` / `minifiedText` are
    /// untouched, so Copy Pretty / Minified stay clean.
    static func attributedString(from document: FormattedDocument,
                                 appearance: Appearance,
                                 fontSize: CGFloat = 12,
                                 showInvisibles: Bool = false) -> AttributedString {
        let theme = Theme.theme(for: appearance)
        var result = AttributedString()
        var index = document.tokens.startIndex
        while index < document.tokens.endIndex {
            let kind = document.tokens[index].kind
            var run = ""
            run.reserveCapacity(32)
            while index < document.tokens.endIndex, document.tokens[index].kind == kind {
                run += document.tokens[index].text
                index += 1
            }
            if showInvisibles {
                appendRevealingInvisibles(run, kind: kind, theme: theme, fontSize: fontSize, into: &result)
            } else {
                var piece = AttributedString(run)
                style(&piece, kind: kind, theme: theme, fontSize: fontSize)
                result.append(piece)
            }
        }
        return result
    }

    /// Maps whitespace to editor-style markers. Newlines keep a real `\n` after
    /// the marker so layout stays line-oriented.
    static func revealInvisibles(in text: String) -> String {
        var out = String()
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case " ": out.append("·")
            case "\t": out.append("⇥")
            case "\n": out.append("↵\n")
            case "\r": out.append("␍")
            default: out.append(character)
            }
        }
        return out
    }

    private static func appendRevealingInvisibles(_ text: String,
                                                  kind: SyntaxToken.Kind,
                                                  theme: Theme,
                                                  fontSize: CGFloat,
                                                  into result: inout AttributedString) {
        var buffer = String()
        var bufferIsInvisible = false

        func flush() {
            guard !buffer.isEmpty else { return }
            var piece = AttributedString(buffer)
            let flushKind = bufferIsInvisible ? SyntaxToken.Kind.whitespace : kind
            let rgb = bufferIsInvisible ? theme.secondaryForeground : theme.color(for: kind)
            piece.foregroundColor = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
            piece.font = .system(
                size: fontSize,
                weight: flushKind == .key || flushKind == .tagName ? .medium : .regular,
                design: .monospaced
            )
            result.append(piece)
            buffer.removeAll(keepingCapacity: true)
        }

        for character in text {
            let (display, isInvisible): (String, Bool) = {
                switch character {
                case " ": return ("·", true)
                case "\t": return ("⇥", true)
                case "\n": return ("↵\n", true)
                case "\r": return ("␍", true)
                default: return (String(character), false)
                }
            }()
            if !buffer.isEmpty, isInvisible != bufferIsInvisible {
                flush()
            }
            bufferIsInvisible = isInvisible
            buffer.append(display)
        }
        flush()
    }

    private static func style(_ piece: inout AttributedString,
                              kind: SyntaxToken.Kind,
                              theme: Theme,
                              fontSize: CGFloat) {
        let rgb = theme.color(for: kind)
        piece.foregroundColor = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        piece.font = .system(
            size: fontSize,
            weight: kind == .key || kind == .tagName ? .medium : .regular,
            design: .monospaced
        )
    }
}

public extension Theme.RGB {
    var color: Color { Color(red: red, green: green, blue: blue) }
}
