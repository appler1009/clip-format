import AppKit
import ClipFormatShared
import SwiftUI

/// The popover shown when the status item is clicked: pretty JSON or XML when
/// the clipboard has some, an explanation when it does not.
extension View {
    /// Pins content smaller than its scroll view to the top left, which
    /// SwiftUI otherwise centres in both axes.
    ///
    /// The unparameterised `defaultScrollAnchor` sets the anchor for every
    /// role — initial offset and size changes as well as alignment — so on
    /// macOS 15 and later only the alignment role is claimed, leaving a
    /// resize while scrolled to keep its position. macOS 14 has only the
    /// blunt form.
    @ViewBuilder
    func topLeadingAnchored() -> some View {
        if #available(macOS 15, *) {
            defaultScrollAnchor(.topLeading, for: .alignment)
        } else {
            defaultScrollAnchor(.topLeading)
        }
    }
}

struct PopoverView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @ObservedObject var preferences: Preferences
    @Environment(\.colorScheme) private var colorScheme

    var openPreferences: () -> Void
    var quit: () -> Void

    private var appearance: Appearance { colorScheme == .dark ? .dark : .light }
    private var theme: Theme { Theme.theme(for: appearance) }
    private var document: FormattedDocument { monitor.document }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        // Sizing belongs to whoever is hosting the view: the popover pins it
        // to contentSize, and the torn-off window lets the user resize.
        .frame(minWidth: 380, idealWidth: 520, maxWidth: .infinity,
               minHeight: 180, idealHeight: 420, maxHeight: .infinity)
        .background(theme.background.color)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(document.isValid ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(statusTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.foreground.color)
            if monitor.isFormatting {
                ProgressView().controlSize(.small)
            }
            Spacer()
            if let detail = statusDetail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryForeground.color)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusTitle: String {
        guard document.isValid else {
            if document.kind == .xml { return "Clipboard isn’t valid XML" }
            // Unrecognised text is not a failed JSON document — do not pretend it is.
            if document.errorTitle == "Can't format" { return "Nothing to format" }
            return "Clipboard isn’t valid JSON"
        }
        switch document.kind {
        case .json: return "Clipboard is JSON"
        case .lineDelimited: return "Clipboard is JSON Lines"
        case .jsonc: return "Clipboard is JSONC"
        case .xml: return "Clipboard is XML"
        }
    }

    private var statusDetail: String? {
        guard document.isValid else { return document.errorMessage }
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(document.source.utf8.count),
                                              countStyle: .file)
        // The record count is the thing worth knowing about a JSON Lines file;
        // the byte count says little about how much is in it.
        let summary = document.kind == .lineDelimited
            ? "\(document.recordCount) \(document.recordCount == 1 ? "record" : "records") · \(bytes)"
            : bytes
        return document.isTruncated ? "\(summary) · truncated" : summary
    }

    @ViewBuilder
    private var content: some View {
        if document.isValid {
            ScrollView([.vertical, .horizontal]) {
                Text(FormatCanvas.attributedString(from: document, appearance: appearance,
                                                fontSize: CGFloat(preferences.fontSize)))
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .topLeadingAnchored()
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Copy some JSON or XML and it will show up here, formatted.")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryForeground.color)
            if !document.rawExcerpt().isEmpty {
                ScrollView {
                    Text(document.rawExcerpt(limit: 1_200))
                        .font(.system(size: CGFloat(max(11, preferences.fontSize - 1)), design: .monospaced))
                        .foregroundStyle(theme.secondaryForeground.color)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(10)
                }
                .topLeadingAnchored()
                .background(theme.secondaryBackground.color)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxHeight: 160)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Copy Pretty") { copy(document.prettyText) }
                .disabled(!document.isValid)
            Button("Copy Minified") { copy(document.minifiedText) }
                .disabled(!document.isValid)
            Spacer()
            Button("A−") { preferences.decreaseFontSize() }
                .disabled(preferences.fontSize <= Preferences.minFontSize)
                .help("Smaller text (⌘−)")
            Button("A+") { preferences.increaseFontSize() }
                .disabled(preferences.fontSize >= Preferences.maxFontSize)
                .help("Larger text (⌘+)")
            Button {
                openPreferences()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Preferences")
            Button {
                quit()
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit ClipFormat")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    /// Writing our own output back bumps `changeCount`; the monitor simply picks
    /// it up on the next tick and re-renders the same document.
    private func copy(_ text: String?) {
        guard let text else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
