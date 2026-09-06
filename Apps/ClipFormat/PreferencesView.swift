import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section("Formatting") {
                Picker("Indent:", selection: $preferences.indentWidth) {
                    Text("2 spaces").tag(2)
                    Text("4 spaces").tag(4)
                    Text("8 spaces").tag(8)
                }
                .pickerStyle(.inline)
                Stepper(value: $preferences.fontSize, in: Preferences.minFontSize...Preferences.maxFontSize) {
                    Text("Font size: \(preferences.fontSize) pt")
                }
                Text("In the popover, ⌘+ and ⌘− change the size.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                Toggle("Show ✓ / ✕ badge", isOn: $preferences.showBadge)
                Text("Off shows plain braces that follow the menu bar’s appearance.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $preferences.launchAtLogin)
                if let error = preferences.launchAtLoginError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Open Login Items in System Settings…") {
                    preferences.openLoginItemsSettings()
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }

            Section("Quick Look") {
                Text("Quick Look uses the same formatting at a fixed 2-space indent. If Spacebar previews of .json files don’t change, keep ClipFormat in Applications, open it once, then run `qlmanage -r` in Terminal.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { preferences.refreshLaunchAtLoginStatus() }
    }
}
