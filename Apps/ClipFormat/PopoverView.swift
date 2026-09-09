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
            if monitor.isFormatting {
                HStack {
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                Divider()
            }
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

    /// The menu-bar badge already says whether the clipboard is usable. This
    /// view only shows a message when there is something to diagnose — a parse
    /// error, a size refusal — not a restatement of "nothing to format".
    private var diagnosticMessage: String? {
        guard let message = document.errorMessage else { return nil }
        switch message {
        case "Not JSON or XML", "Clipboard is empty":
            return nil
        default:
            return message
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let diagnosticMessage {
                Text(diagnosticMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryForeground.color)
            }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
