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

    /// Liquid Glass per control on Tahoe — same idea as toolbar items, not one
    /// enclosing capsule. Padding is applied *before* the glass so the shape
    /// has room around the glyph instead of hugging it. Earlier systems stay
    /// plain so they do not invent a group chrome the window never had.
    @ViewBuilder
    func toolbarLikeGlass() -> some View {
        if #available(macOS 26, *) {
            self
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .glassEffect(.regular.interactive())
        } else {
            self
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
    }
}

/// Where this view is hosted. Both put actions in the same top-trailing glass
/// cluster; only the popover adds the leading tear-off grabber.
enum PopoverChrome {
    case popover
    case window
}

struct PopoverView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @ObservedObject var preferences: Preferences
    @Environment(\.colorScheme) private var colorScheme

    var openPreferences: () -> Void
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
            chromeTopBar(showsDetachHandle: true)
            formattingBanner
            documentBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var windowBody: some View {
        VStack(spacing: 0) {
            // Same action cluster as the popover — not an NSToolbar — so spacing
            // and glass match exactly. The system title bar still owns traffic
            // lights and window dragging.
            chromeTopBar(showsDetachHandle: false)
            formattingBanner
            documentBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // fullSizeContentView already draws under the title bar; ignore the
        // safe-area inset so the actions sit level with the traffic lights
        // instead of one row below them.
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Leading grabber only in the popover; both hosts share the trailing actions.
    private func chromeTopBar(showsDetachHandle: Bool) -> some View {
        HStack(spacing: 12) {
            if showsDetachHandle {
                detachHandle
            } else {
                // Title is hidden and the bar is transparent, so leave room for
                // the traffic lights instead of drawing under them.
                Color.clear.frame(width: 68, height: 28)
            }
            Spacer(minLength: 16)
            actionBar
        }
        .padding(.horizontal, 14)
        // Window chrome lives in the title-bar band; keep top padding tight so
        // glass controls center with the traffic lights. Popover keeps a bit
        // more air under the popover edge.
        .padding(.top, showsDetachHandle ? 10 : 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var actionBar: some View {
        // Spacing has to live both in the HStack and in GlassEffectContainer —
        // the container's spacing is what keeps neighbouring glass shapes apart.
        let gap: CGFloat = 20
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: gap) {
                HStack(spacing: gap) {
                    copyMenu.toolbarLikeGlass()
                    smallerTextButton.toolbarLikeGlass()
                    largerTextButton.toolbarLikeGlass()
                    preferencesButton.toolbarLikeGlass()
                }
                .font(.system(size: 13))
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        } else {
            HStack(spacing: gap) {
                copyMenu.toolbarLikeGlass()
                smallerTextButton.toolbarLikeGlass()
                largerTextButton.toolbarLikeGlass()
                preferencesButton.toolbarLikeGlass()
            }
            .font(.system(size: 13))
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
    }

    /// One Copy control; Pretty / Minified live in the menu where labels fit.
    private var copyMenu: some View {
        Menu {
            Button("Pretty") { copy(document.prettyText) }
                .disabled(!document.isValid)
            Button("Minified") { copy(document.minifiedText) }
                .disabled(!document.isValid)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .help("Copy formatted clipboard")
        .disabled(!document.isValid)
    }

    private var smallerTextButton: some View {
        Button {
            preferences.decreaseFontSize()
        } label: {
            Label("Smaller", systemImage: "textformat.size.smaller")
        }
        .disabled(preferences.fontSize <= Preferences.minFontSize)
        .help("Smaller text (⌘−)")
    }

    private var largerTextButton: some View {
        Button {
            preferences.increaseFontSize()
        } label: {
            Label("Larger", systemImage: "textformat.size.larger")
        }
        .disabled(preferences.fontSize >= Preferences.maxFontSize)
        .help("Larger text (⌘+)")
    }

    private var preferencesButton: some View {
        Button {
            openPreferences()
        } label: {
            Label("Preferences", systemImage: "gearshape")
        }
        .help("Preferences")
    }

    /// Leading grabber. AppKit already tears the popover off when the user
    /// drags it; this only says where to start.
    private var detachHandle: some View {
        Capsule()
            .fill(theme.secondaryForeground.color.opacity(0.4))
            .frame(width: 36, height: 4)
            .frame(width: 44, height: 28, alignment: .center)
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

    /// Writing our own output back bumps `changeCount`; the monitor simply picks
    /// it up on the next tick and re-renders the same document.
    private func copy(_ text: String?) {
        guard let text else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
