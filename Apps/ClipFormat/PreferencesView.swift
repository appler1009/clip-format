import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Picker("Indent:", selection: $preferences.indentWidth) {
                Text("2 spaces").tag(2)
                Text("4 spaces").tag(4)
                Text("8 spaces").tag(8)
            }
            .pickerStyle(.inline)

            Toggle("Show ✓ / ✕ badge in the menu bar", isOn: $preferences.showBadge)
            Toggle("Launch at login", isOn: $preferences.launchAtLogin)

            Section {
                Text("Quick Look uses the same formatting. If Spacebar previews of .json files don’t change, open ClipFormat once from Applications, then run `qlmanage -r` in Terminal.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}
