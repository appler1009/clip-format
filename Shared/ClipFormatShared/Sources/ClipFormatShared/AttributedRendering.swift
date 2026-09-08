import Foundation
import SwiftUI

public extension FormatCanvas {
    /// The popover's counterpart to `html(from:)` — same tokens, same theme.
    static func attributedString(from document: FormattedDocument,
                                 appearance: Appearance,
                                 fontSize: CGFloat = 12) -> AttributedString {
        let theme = Theme.theme(for: appearance)
        var result = AttributedString()
        for token in document.tokens {
            var piece = AttributedString(token.text)
            let rgb = theme.color(for: token.kind)
            piece.foregroundColor = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
            piece.font = .system(size: fontSize, weight: token.kind == .key ? .medium : .regular, design: .monospaced)
            result.append(piece)
        }
        return result
    }
}

public extension Theme.RGB {
    var color: Color { Color(red: red, green: green, blue: blue) }
}
