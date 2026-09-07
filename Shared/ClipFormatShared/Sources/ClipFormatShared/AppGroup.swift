import Foundation

/// Shared container for the menu-bar app and the Quick Look extension.
///
/// Register `identifier` as an App Group on the Apple Developer account
/// (Identifiers → App Groups) and enable it on both App IDs. Automatic
/// signing then stamps both binaries; without that step the suite is just
/// a private defaults file the extension cannot see.
public enum AppGroup {
    public static let identifier = "TN2RQ5P647.group.com.appler1009.ClipFormat"

    /// Preference keys written by the app and read by Quick Look.
    public enum Key {
        public static let indentWidth = "indentWidth"
        public static let fontSize = "fontSize"
        public static let showBadge = "showBadge"
    }

    public static let defaultIndentWidth = 2
    public static let minFontSize = 9
    public static let maxFontSize = 28
    public static let defaultFontSize = 12

    /// The group suite when the entitlement is in place; `.standard` otherwise
    /// so a local unsigned build still has somewhere to store prefs.
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

/// Formatting knobs Quick Look applies when it builds a preview.
public struct SharedFormattingPreferences: Sendable, Equatable {
    public var indentWidth: Int
    public var fontSize: Int

    public init(indentWidth: Int = AppGroup.defaultIndentWidth,
                fontSize: Int = AppGroup.defaultFontSize) {
        self.indentWidth = indentWidth
        self.fontSize = min(AppGroup.maxFontSize, max(AppGroup.minFontSize, fontSize))
    }

    public static func load(from defaults: UserDefaults = AppGroup.defaults) -> SharedFormattingPreferences {
        let indent = defaults.object(forKey: AppGroup.Key.indentWidth) as? Int
            ?? AppGroup.defaultIndentWidth
        let font = defaults.object(forKey: AppGroup.Key.fontSize) as? Int
            ?? AppGroup.defaultFontSize
        return SharedFormattingPreferences(indentWidth: indent, fontSize: font)
    }
}
