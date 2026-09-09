import AppKit
import ClipFormatShared
import SwiftUI

/// The popover shown when the status item is clicked: pretty JSON or XML when
/// the clipboard has some, an explanation when it does not. The same view is
/// hosted in the torn-off window with chrome moved into the title bar.
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

/// Where this view is hosted. The popover keeps a bottom footer and a tear-off
/// grabber; the window lifts the same actions into the title-bar toolbar so
/// Tahoe can put them on Liquid Glass.
enum PopoverChrome {
    case popover
    case window
}

struct PopoverView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @ObservedObject var preferences: Preferences
    @Environment(\.colorScheme) private var colorScheme

    var openPreferences: () -> Void
    var quit: () -> Void
    var chrome: PopoverChrome = .popover

    private var appearance: Appearance { colorScheme == .dark ? .dark : .light }
    private var theme: Theme { Theme.theme(for: appearance) }
    private var document: FormattedDocument { monitor.document }

    var body: some View {
        Group {
            switch chrome {
            case .popover:
                popoverBody
            case .window:
                windowBody
            }
        }
        // Sizing belongs to whoever is hosting the view: the popover pins it
        // to contentSize, and the torn-off window lets the user resize.
        .frame(minWidth: 380, idealWidth: 520, maxWidth: .infinity,
               minHeight: 180, idealHeight: 420, maxHeight: .infinity)
        .background(theme.background.color)
    }

    private var popoverBody: some View {
        VStack(spacing: 0) {
            detachHandle
            formattingBanner
            documentBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
    }

    private var windowBody: some View {
        VStack(spacing: 0) {
            formattingBanner
            documentBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Copy Pretty") { copy(document.prettyText) }
                    .disabled(!document.isValid)
                Button("Copy Minified") { copy(document.minifiedText) }
                    .disabled(!document.isValid)
            }
            ToolbarItemGroup(placement: .primaryAction) {
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
                .help("Preferences")
                Button {
                    quit()
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit ClipFormat")
            }
        }
        // Let the system draw the toolbar glass (Liquid Glass on Tahoe) rather
        // than painting a material that would sit on top of it.
        .toolbarBackground(.automatic, for: .windowToolbar)
    }

    /// A quiet grabber. AppKit already tears the popover off when the user
    /// drags it; this only says where to start.
    private var detachHandle: some View {
        Capsule()
            .fill(theme.secondaryForeground.color.opacity(0.4))
            .frame(width: 36, height: 4)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .help("Drag to tear off into a window")
            .onHover { hovering in
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .accessibilityLabel("Tear off")
            .accessibilityHint("Drag to keep this view open as a window")
    }

    @ViewBuilder
    private var formattingBanner: some View {
        if monitor.isFormatting {
            HStack {
                ProgressView().controlSize(.small)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
        }
    }

    @ViewBuilder
    private var documentBody: some View {
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
        Group {
            if !document.rawExcerpt().isEmpty {
                ScrollView {
                    Text(document.rawExcerpt(limit: 1_200))
                        .font(.system(size: CGFloat(max(11, preferences.fontSize - 1)), design: .monospaced))
                        .foregroundStyle(theme.secondaryForeground.color)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                }
                .topLeadingAnchored()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
