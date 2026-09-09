import AppKit

/// The menu-bar glyph: template braces, optionally badged with whether the
/// clipboard holds something this app can format.
///
/// Drawing happens inside `NSImage(size:flipped:drawingHandler:)` so the braces
/// pick up the correct label colour every time the menu bar redraws — including
/// when the user flips appearance or turns on a tinted desktop.
enum StatusItemIcon {
    enum State {
        case valid
        case invalid
        case neutral

        var badgeColor: NSColor? {
            switch self {
            case .valid: return .systemGreen
            case .invalid: return .systemRed
            case .neutral: return nil
            }
        }

        var badgeSymbol: String? {
            switch self {
            case .valid: return "checkmark"
            case .invalid: return "xmark"
            case .neutral: return nil
            }
        }

        var accessibilityDescription: String {
            switch self {
            case .valid: return "ClipFormat — clipboard contains something ClipFormat can format"
            case .invalid: return "ClipFormat — clipboard has nothing to format"
            case .neutral: return "ClipFormat"
            }
        }
    }

    private static let size = NSSize(width: 20, height: 18)

    static func image(for state: State) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            draw(state: state)
            return true
        }
        image.isTemplate = state.badgeColor == nil
        image.accessibilityDescription = state.accessibilityDescription
        return image
    }

    private static func draw(state: State) {
        let braces = NSImage(systemSymbolName: "curlybraces", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        let bracesSize = braces?.size ?? .zero
        let bracesRect = NSRect(
            x: (size.width - bracesSize.width) / 2 - (state.badgeColor == nil ? 0 : 1.5),
            y: (size.height - bracesSize.height) / 2,
            width: bracesSize.width,
            height: bracesSize.height
        )

        if state.badgeColor == nil {
            braces?.draw(in: bracesRect)
            return
        }

        NSColor.labelColor.set()
        braces?.draw(in: bracesRect, from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: true, hints: nil)
        bracesRect.fill(using: .sourceAtop)

        drawBadge(state: state)
    }

    private static func drawBadge(state: State) {
        guard let color = state.badgeColor, let symbolName = state.badgeSymbol else { return }
        let diameter: CGFloat = 9
        let badgeRect = NSRect(x: size.width - diameter, y: 0, width: diameter, height: diameter)

        // Knock a ring out of the braces so the badge stays legible when it
        // overlaps them.
        NSGraphicsContext.current?.saveGraphicsState()
        NSColor.clear.set()
        NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1.25, dy: -1.25)).fill(using: .copy)
        NSGraphicsContext.current?.restoreGraphicsState()

        color.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()

        // The glyph is coloured through a palette configuration. Tinting it the
        // way the braces are tinted — draw, then fill .sourceAtop — would paint
        // the whole rect, badge circle included, solid white.
        let configuration = NSImage.SymbolConfiguration(pointSize: 6.5, weight: .black)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        let glyph = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        guard let glyph else { return }
        let glyphRect = NSRect(
            x: badgeRect.midX - glyph.size.width / 2,
            y: badgeRect.midY - glyph.size.height / 2,
            width: glyph.size.width,
            height: glyph.size.height
        )
        glyph.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: true, hints: nil)
    }
}

private extension NSBezierPath {
    func fill(using operation: NSCompositingOperation) {
        NSGraphicsContext.current?.compositingOperation = operation
        fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }
}

private extension NSRect {
    func fill(using operation: NSCompositingOperation) {
        NSGraphicsContext.current?.compositingOperation = operation
        NSBezierPath(rect: self).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }
}

