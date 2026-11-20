import Foundation
import SwiftUI

public extension FormatCanvas {
    /// The popover's counterpart to `html(from:)` — same tokens, same theme.
    ///
    /// Neighbouring tokens of the same kind are coalesced into one
    /// `AttributedString` run (mirroring the HTML renderer) so a pretty-printed
    /// object does not allocate one piece per punctuation mark.
    ///
    /// Font *size* is deliberately not baked in — hosts apply
    /// `.font(.system(size:design: .monospaced))` on the `Text`, so ⌘+ / ⌘−
    /// only restyle the view. Keys / tag names use a strong presentation intent
    /// for medium weight under that base font.
    ///
    /// When `showInvisibles` is on, spaces / tabs / line breaks become visible
    /// glyphs in the attributed string only. `prettyText` / `minifiedText` are
    /// untouched, so Copy Pretty / Minified stay clean.
    static func attributedString(from document: FormattedDocument,
                                 appearance: Appearance,
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
                appendRevealingInvisibles(run, kind: kind, theme: theme, into: &result)
            } else {
                result.append(styled(run, kind: kind, theme: theme))
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
            if let glyph = invisibleGlyph(for: character) {
                out += glyph
            } else {
                out.append(character)
            }
        }
        return out
    }

    /// The marker shown for a whitespace character, or nil for anything else.
    private static func invisibleGlyph(for character: Character) -> String? {
        switch character {
        case " ": return "·"
        case "\t": return "⇥"
        case "\n": return "↵\n"
        case "\r": return "␍"
        default: return nil
        }
    }

    /// Splits a run into visible text, coloured as its kind, and whitespace
    /// markers, which recede in the secondary colour.
    private static func appendRevealingInvisibles(_ text: String,
                                                  kind: SyntaxToken.Kind,
                                                  theme: Theme,
                                                  into result: inout AttributedString) {
        var buffer = String()
        var bufferIsInvisible = false

        func flush() {
            guard !buffer.isEmpty else { return }
            result.append(bufferIsInvisible
                ? styled(buffer, color: theme.secondaryForeground, emphasized: false)
                : styled(buffer, kind: kind, theme: theme))
            buffer.removeAll(keepingCapacity: true)
        }

        for character in text {
            let glyph = invisibleGlyph(for: character)
            let isInvisible = glyph != nil
            if !buffer.isEmpty, isInvisible != bufferIsInvisible {
                flush()
            }
            bufferIsInvisible = isInvisible
            if let glyph { buffer += glyph } else { buffer.append(character) }
        }
        flush()
    }

    private static func styled(_ text: String, kind: SyntaxToken.Kind, theme: Theme) -> AttributedString {
        styled(text, color: theme.color(for: kind), emphasized: kind == .key || kind == .tagName)
    }

    private static func styled(_ text: String, color: Theme.RGB, emphasized: Bool) -> AttributedString {
        var piece = AttributedString(text)
        piece.foregroundColor = color.color
        if emphasized {
            piece.inlinePresentationIntent = .stronglyEmphasized
        }
        return piece
    }
}

public extension Theme.RGB {
    var color: Color { Color(red: red, green: green, blue: blue) }
}
