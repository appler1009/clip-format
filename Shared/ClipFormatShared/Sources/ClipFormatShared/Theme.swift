import Foundation

/// The two appearances ClipFormat renders for. Quick Look tells us which one
/// the previewing window is using; the popover follows the system.
public enum Appearance: String, Sendable, CaseIterable {
    case light
    case dark
}

/// Colours for the formatted view, shared by the popover and Quick Look so the
/// two never drift apart.
public struct Theme: Sendable {
    public struct RGB: Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(_ hex: UInt32) {
            red = Double((hex >> 16) & 0xFF) / 255
            green = Double((hex >> 8) & 0xFF) / 255
            blue = Double(hex & 0xFF) / 255
        }

        public var hexString: String {
            String(format: "#%02x%02x%02x", Int(red * 255), Int(green * 255), Int(blue * 255))
        }
    }

    public let background: RGB
    public let secondaryBackground: RGB
    public let foreground: RGB
    public let secondaryForeground: RGB
    public let key: RGB
    public let string: RGB
    public let number: RGB
    public let literal: RGB
    public let punctuation: RGB
    public let error: RGB

    public static let light = Theme(
        background: RGB(0xFDFDFB),
        secondaryBackground: RGB(0xF1F1EE),
        foreground: RGB(0x1C1C1E),
        secondaryForeground: RGB(0x6E6E73),
        key: RGB(0x1D4ED8),
        string: RGB(0x0F766E),
        number: RGB(0x9333EA),
        literal: RGB(0xC2410C),
        punctuation: RGB(0x9A9A9F),
        error: RGB(0xC0392B)
    )

    public static let dark = Theme(
        background: RGB(0x1C1C1E),
        secondaryBackground: RGB(0x2A2A2D),
        foreground: RGB(0xE6E6E9),
        secondaryForeground: RGB(0x98989F),
        key: RGB(0x7AA2F7),
        string: RGB(0x8FD48A),
        number: RGB(0xD9A5F5),
        literal: RGB(0xF0906E),
        punctuation: RGB(0x6E7681),
        error: RGB(0xFF6B6B)
    )

    public static func theme(for appearance: Appearance) -> Theme {
        appearance == .dark ? .dark : .light
    }

    public func color(for kind: JSONToken.Kind) -> RGB {
        switch kind {
        case .key: return key
        case .string: return string
        case .number: return number
        case .bool, .null: return literal
        case .punctuation: return punctuation
        case .whitespace: return foreground
        }
    }
}
